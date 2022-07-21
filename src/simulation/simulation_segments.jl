"""
Defines how a simulation can be segment into segments and run in parallel.
"""
struct SimulationSegments <: IS.InfrastructureSystemsType
    "Number of steps in the simulation"
    num_steps::Int
    "Number of steps in each segment"
    period::Int
    "Number of steps that a segment overlaps with the previous segment"
    num_overlap_steps::Int

    function SimulationSegments(num_steps, period, num_overlap_steps=0)
        if num_overlap_steps > period
            error(
                "period=$period must be greater than num_overlap_steps=$num_overlap_steps",
            )
        end
        if period >= num_steps
            error("period=$period must be less than simulation steps=$num_steps")
        end
        return new(num_steps, period, num_overlap_steps)
    end
end

function SimulationSegments(; num_steps, period, num_overlap_steps)
    return SimulationSegments(num_steps, period, num_overlap_steps)
end

"""
Return the number of segments in the simulation.
"""
get_num_segments(x::SimulationSegments) = Int(ceil(x.num_steps / x.period))

"""
Return a UnitRange for the steps in the segment with the given index. Includes overlap.
"""
function get_absolute_step_range(segments::SimulationSegments, index::Int)
    num_segments = _check_segment_index(segments, index)
    start_index = segments.period * (index - 1) + 1
    if index < num_segments
        end_index = start_index + segments.period - 1
    else
        end_index = segments.num_steps
    end

    if index > 1
        start_index -= segments.num_overlap_steps
    end

    return start_index:end_index
end

"""
Return the step offset for valid data at the given index.
"""
function get_valid_step_offset(segments::SimulationSegments, index::Int)
    _check_segment_index(segments, index)
    return index == 1 ? 1 : segments.num_overlap_steps + 1
end

"""
Return the length of valid data at the given index.
"""
function get_valid_step_length(segments::SimulationSegments, index::Int)
    num_segments = _check_segment_index(segments, index)
    if index < num_segments
        return segments.period
    end

    remainder = segments.num_steps % segments.period
    return remainder == 0 ? segments.period : remainder
end

function _check_segment_index(segments::SimulationSegments, index::Int)
    num_segments = get_num_segments(segments)
    if index <= 0 || index > num_segments
        error("index=$index=inde must be > 0 and <= $num_segments")
    end

    return num_segments
end

function IS.serialize(segments::SimulationSegments)
    return IS.serialize_struct(segments)
end

function process_simulation_segment_cli_args(build_function, execute_function, args...)
    length(args) < 2 && error("Usage: setup|execute|join [options]")
    function config_logging(filename)
        return IS.configure_logging(
            console=true,
            console_stream=stderr,
            console_level=Logging.Warn,
            file=true,
            filename=filename,
            file_level=Logging.Info,
            file_mode="w",
            tracker=nothing,
            set_global=true,
        )
    end

    function throw_if_missing(actual, required, label)
        diff = setdiff(required, actual)
        !isempty(diff) && error("Missing required options for $label: $diff")
    end

    operation = args[1]
    options = Dict{String, String}()
    for opt in args[2:end]
        !startswith(opt, "--") && error("All options must start with '--': $opt")
        fields = split(opt[3:end], "=")
        length(fields) != 2 && error("All options must use the format --name=value: $opt")
        options[fields[1]] = fields[2]
    end

    if haskey(options, "output-dir")
        output_dir = options["output-dir"]
    elseif haskey(ENV, "JADE_RUNTIME_OUTPUT")
        output_dir = ENV["JADE_RUNTIME_OUTPUT"]
    else
        error("output-dir must be specified as a CLI option or environment variable")
    end

    if operation == "setup"
        required = Set(("simulation-name", "num-steps", "num-period-steps"))
        throw_if_missing(keys(options), required, operation)
        if !haskey(options, "num-overlap-steps")
            options["num-overlap-steps"] = "0"
        end

        num_steps = parse(Int, options["num-steps"])
        num_period_steps = parse(Int, options["num-period-steps"])
        num_overlap_steps = parse(Int, options["num-overlap-steps"])
        segments = SimulationSegments(num_steps, num_period_steps, num_overlap_steps)
        config_logging(joinpath(output_dir, "setup_segment_simulation.log"))
        build_function(output_dir, options["simulation-name"], segments)
    elseif operation == "execute"
        throw_if_missing(keys(options), Set(("simulation-name", "index")), operation)
        index = parse(Int, options["index"])
        base_dir = joinpath(output_dir, options["simulation-name"])
        segment_output_dir = joinpath(base_dir, "simulation_segments", string(index))
        config_file = joinpath(base_dir, "simulation_segments", "config.json")
        config = open(config_file, "r") do io
            JSON3.read(io, Dict)
        end
        segments = IS.deserialize(SimulationSegments, config)
        config_logging(joinpath(segment_output_dir, "run_segment_simulation.log"))
        sim =
            build_function(segment_output_dir, options["simulation-name"], segments, index)
        execute_function(sim)
    elseif operation == "join"
        throw_if_missing(keys(options), Set(("simulation-name",)), operation)
        base_dir = joinpath(output_dir, options["simulation-name"])
        config_file = joinpath(base_dir, "simulation_segments", "config.json")
        config = open(config_file, "r") do io
            JSON3.read(io, Dict)
        end
        segments = IS.deserialize(SimulationSegments, config)
        config_logging(joinpath(base_dir, "join_segmented_simulation.log"))
        join_simulation(base_dir)
    else
        error("Unsupported operation=$operation")
    end

    return
end
