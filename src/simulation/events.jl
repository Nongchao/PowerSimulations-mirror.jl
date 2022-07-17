"""
Struct to simulation a device trip
"""
struct UnplannedOutage <: EventType
    device::PSY.Device
    timestamp::Dates.DateTime
end
