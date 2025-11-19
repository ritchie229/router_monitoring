#!/usr/bin/env lua

-- Путь к файлу, куда Prometheus читает метрики
local output_file = "/var/lib/node_exporter/textfile_collector/wifi.prom"

local ubus = require "ubus"
local iwinfo = require "iwinfo"

local function metric(name, value, labels)
    local label_str = ""
    if labels then
        local parts = {}
        for k,v in pairs(labels) do
            table.insert(parts, k .. "=\"" .. tostring(v) .. "\"")
        end
        if #parts > 0 then
            label_str = "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return string.format("%s%s %s\n", name, label_str, tostring(value))
end

local function scrape()
    local u = ubus.connect()
    if not u then
        return "-- could not connect to ubus\n"
    end

    local status = u:call("network.wireless", "status", {})
    local lines = {}

    for dev, dev_table in pairs(status) do
	
        for _, intf in ipairs(dev_table['interfaces']) do
            local ifname = intf['ifname']
            if ifname then
                local iw = iwinfo[iwinfo.type(ifname)]
                if iw then
                    local labels = {
                        channel = iw.channel(ifname),
                        ssid = iw.ssid(ifname),
                        bssid = string.lower(iw.bssid(ifname)),
                        mode = iw.mode(ifname),
                        ifname = ifname,
                        country = iw.country(ifname),
                        frequency = iw.frequency(ifname),
                        device = dev,
                    }

                    local qc = iw.quality(ifname) or 0
                    local qm = iw.quality_max(ifname) or 0
                    local quality = 0
                    if qc > 0 and qm > 0 then
                        quality = math.floor((100 / qm) * qc)
                    end

                    table.insert(lines, metric("wifi_network_quality", quality, labels))
                    table.insert(lines, metric("wifi_network_noise_dbm", iw.noise(ifname) or 0, labels))
                    table.insert(lines, metric("wifi_network_bitrate", iw.bitrate(ifname) or 0, labels))
                    table.insert(lines, metric("wifi_network_signal_dbm", iw.signal(ifname) or -255, labels))
                end
            end
        end
    end

    return table.concat(lines)
end

-- Сохраняем метрики в файл для Node Exporter
local f = io.open(output_file, "w")
if f then
    f:write(scrape())
    f:close()
else
    io.stderr:write("Cannot open file: " .. output_file .. "\n")
end
