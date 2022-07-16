"""
Struct to simulation a device trip
"""
struct UnplanedOutage <: EventType
    device::PSY.Device
    timestamp::Dates.DateTime
end
