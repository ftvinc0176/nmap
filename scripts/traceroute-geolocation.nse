local http = require "http"
local io = require "io"
local json = require "json"
local stdnse = require "stdnse"
local tab = require "tab"
local table = require "table"
local ipOps = require "ipOps"

description = [[
Lists the geographic locations of each hop in a traceroute and optionally
saves the results to a KML file, plottable on Google earth and maps.
]]

---
-- @usage
-- nmap --traceroute --script traceroute-geolocation
--
-- @output
-- | traceroute-geolocation: 
-- |   hop  RTT     ADDRESS                                               GEOLOCATION
-- |   1    ...
-- |   2    ...
-- |   3    ...
-- |   4    ...
-- |   5    16.76   e4-0.barleymow.stk.router.colt.net (194.68.128.104)   62,15 Sweden (Unknown)
-- |   6    48.61   te0-0-2-0-crs1.FRA.router.colt.net (212.74.65.49)     54,-2 United Kingdom (Unknown)
-- |   7    57.16   87.241.37.146                                         42,12 Italy (Unknown)
-- |   8    157.85  212.162.64.146                                        42,12 Italy (Unknown)
-- |   9    ...
-- |_  10   ...
--
-- @args traceroute-geolocation.kmlfile full path and name of file to write KML
--       data to. The KML file can be used in Google earth or maps to plot the
--       traceroute data.
--


author = "Patrik Karlsson"
license = "Same as Nmap--See http://nmap.org/book/man-legal.html"
categories = {"safe", "external", "discovery"}

local arg_kmlfile = stdnse.get_script_args(SCRIPT_NAME .. ".kmlfile")

hostrule = function(host)
	if ( not(host.traceroute) ) then
		return false
	end
	return true
end

--
-- GeoPlugin requires no API key and has no limitations on lookups
--
local function geoLookup(ip)
	local response = http.get("www.geoplugin.net", 80, "/json.gp?ip="..ip)
	local stat, loc = json.parse(response.body:match("geoPlugin%((.+)%)"))

	if not stat then return nil end
	local output = {}
	local regionName = (loc.geoplugin_regionName == json.NULL) and "Unknown" or loc.geoplugin_regionName
	return loc.geoplugin_latitude, loc.geoplugin_longitude, regionName, loc.geoplugin_countryName
end

local function createKMLFile(filename, coords)
	local header = '<?xml version="1.0" encoding="UTF-8"?><kml xmlns="http://earth.google.com/kml/2.0"><Document><Placemark><LineString><coordinates>\r\n'
	local footer = '</coordinates></LineString><Style><LineStyle><color>#ff0000ff</color></LineStyle></Style></Placemark></Document></kml>'

	local output = ""
	for _, coord in ipairs(coords) do
		output = output .. ("%s,%s, 0.\r\n"):format(coord.lon, coord.lat)
	end

	local f = io.open(filename, "w")
	if ( not(f) ) then
		return false, "Failed to create KML file"
	end
	f:write(header .. output .. footer)
	f:close()
	
	return true
end

action = function(host)

	local output = tab.new(4)
	local coordinates = {}
	
	tab.addrow(output, "HOP", "RTT", "ADDRESS", "GEOLOCATION")
	for count = 1, #host.traceroute do
		local hop = host.traceroute[count]
		-- avoid timedout hops, marked as empty entries
		-- do not add the current scanned host.ip
		if hop.ip then
			local name = ""
			if ( hop.name ) then
				name = ("%s (%s)"):format(hop.name or "", hop.ip)
			else
				name = ("%s"):format(hop.ip)
			end
			local rtt = tonumber(hop.times.srtt) * 1000
			if ( not(ipOps.isPrivate(hop.ip) ) ) then
				local lat, lon, reg, ctry = geoLookup(hop.ip)
				table.insert(coordinates, { hop = count, lat = lat, lon = lon })
				tab.addrow( output, count, ("%.2f"):format(rtt), name, ("%d,%d %s (%s)"):format(lat, lon, ctry, reg) )
			else
				tab.addrow( output, count, ("%.2f"):format(rtt), name, ("%s,%s"):format("- ", "- "))
			end
		else
			tab.addrow( output, count, "...")
		end
	end
  
	if ( #output > 1 ) then
		output = tab.dump(output)
		if ( arg_kmlfile ) then
			if ( not(createKMLFile(arg_kmlfile, coordinates)) ) then
				output = output .. ("\n\nERROR: Failed to write KML to file: %s"):format(arg_kmlfile)
			end
		end
		return stdnse.format_output(true, output)
	end

end
