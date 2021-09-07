"""Default PowerSimulations Emulation Problem Type"""
struct GenericEmulationProblem <: EmulationProblem end

"""
    EmulationModel(::Type{M},
    template::ProblemTemplate,
    sys::PSY.System,
    jump_model::Union{Nothing, JuMP.Model}=nothing;
    kwargs...) where {M<:EmulationProblem,
                      T<:PM.AbstractPowerFormulation}

This builds the optimization problem of type M with the specific system and template.

# Arguments

- `::Type{M} where M<:EmulationProblem`: The abstract Emulation model type
- `template::ProblemTemplate`: The model reference made up of transmission, devices,
                                          branches, and services.
- `sys::PSY.System`: the system created using Power Systems
- `jump_model::Union{Nothing, JuMP.Model}`: Enables passing a custom JuMP model. Use with care

# Output

- `model::EmulationModel`: The Emulation model containing the model type, built JuMP model, Power
Systems system.

# Example

```julia
template = ProblemTemplate(CopperPlatePowerModel, devices, branches, services)
OpModel = EmulationModel(MockEmulationProblem, template, system)
```

# Accepted Key Words

- `optimizer`: The optimizer that will be used in the optimization model.
- `warm_start::Bool`: True will use the current Emulation point in the system to initialize variable values. False initializes all variables to zero. Default is true
- `system_to_file::Bool:`: True to create a copy of the system used in the model. Default true.
- `export_pwl_vars::Bool`: True to export all the pwl intermediate variables. It can slow down significantly the solve time. Default to false.
- `allow_fails::Bool`: True to allow the simulation to continue even if the optimization step fails. Use with care, default to false.
- `optimizer_log_print::Bool`: True to print the optimizer solve log. Default to false.
- `direct_mode_optimizer::Bool` True to use the solver in direct mode. Creates a [JuMP.direct_model](https://jump.dev/JuMP.jl/dev/reference/models/#JuMP.direct_model). Default to false.
- `initial_time::Dates.DateTime`: Initial Time for the model solve
- `time_series_cache_size::Int`: Size in bytes to cache for each time array. Default is 1 MiB. Set to 0 to disable.
"""
mutable struct EmulationModel{M <: EmulationProblem} <: OperationModel
    name::Symbol
    template::ProblemTemplate
    sys::PSY.System
    internal::ModelInternal
    store::InMemoryModelStore # might be extended to other stores for simulation
    ext::Dict{String, Any}

    function EmulationModel{M}(
        template::ProblemTemplate,
        sys::PSY.System,
        settings::Settings,
        jump_model::Union{Nothing, JuMP.Model} = nothing;
        name = nothing,
    ) where {M <: EmulationProblem}
        if name === nothing
            name = Symbol(typeof(template))
        elseif name isa String
            name = Symbol(name)
        end
        _, ts_count, forecast_count = PSY.get_time_series_counts(sys)
        if ts_count < 1
            error(
                "The system does not contain Static TimeSeries data. An Emulation model can't be formulated.",
            )
        end
        internal = ModelInternal(
            OptimizationContainer(sys, settings, jump_model, PSY.SingleTimeSeries),
        )
        new{M}(
            name,
            template,
            sys,
            internal,
            InMemoryModelStore(EmulationModelOptimizerResults),
            Dict{String, Any}(),
        )
    end
end

function EmulationModel{M}(
    template::ProblemTemplate,
    sys::PSY.System,
    jump_model::Union{Nothing, JuMP.Model} = nothing;
    name = nothing,
    optimizer = nothing,
    warm_start = true,
    system_to_file = true,
    export_pwl_vars = false,
    allow_fails = false,
    optimizer_log_print = false,
    direct_mode_optimizer = false,
    initial_time = UNSET_INI_TIME,
    time_series_cache_size::Int = IS.TIME_SERIES_CACHE_SIZE_BYTES,
) where {M <: EmulationProblem}
    settings = Settings(
        sys;
        initial_time = initial_time,
        optimizer = optimizer,
        time_series_cache_size = time_series_cache_size,
        warm_start = warm_start,
        system_to_file = system_to_file,
        export_pwl_vars = export_pwl_vars,
        allow_fails = allow_fails,
        optimizer_log_print = optimizer_log_print,
        direct_mode_optimizer = direct_mode_optimizer,
        horizon = 1,
    )
    return EmulationModel{M}(template, sys, settings, jump_model, name = name)
end

"""
    EmulationModel(::Type{M},
    template::ProblemTemplate,
    sys::PSY.System,
    optimizer::MOI.OptimizerWithAttributes,
    jump_model::Union{Nothing, JuMP.Model}=nothing;
    kwargs...) where {M <: EmulationProblem}
This builds the optimization problem of type M with the specific system and template
# Arguments
- `::Type{M} where M<:EmulationProblem`: The abstract Emulation model type
- `template::ProblemTemplate`: The model reference made up of transmission, devices,
                                          branches, and services.
- `sys::PSY.System`: the system created using Power Systems
- `jump_model::Union{Nothing, JuMP.Model}`: Enables passing a custom JuMP model. Use with care
# Output
- `Stage::EmulationProblem`: The Emulation model containing the model type, unbuilt JuMP model, Power
Systems system.
# Example
```julia
template = ProblemTemplate(CopperPlatePowerModel, devices, branches, services)
problem = EmulationModel(MyOpProblemType template, system, optimizer)
```
# Accepted Key Words
- `initial_time::Dates.DateTime`: Initial Time for the model solve
- `warm_start::Bool` True will use the current Emulation point in the system to initialize variable values. False initializes all variables to zero. Default is true
- `export_pwl_vars::Bool` True will write the results of the piece-wise-linear intermediate variables. Slows down the simulation process significantly
- `allow_fails::Bool` True will allow the simulation to continue if the optimizer can't find a solution. Use with care, can lead to unwanted behaviour or results
- `optimizer_log_print::Bool` Uses JuMP.unset_silent() to print the optimizer's log. By default all solvers are set to `MOI.Silent()`
- `name`: name of model, string or symbol; defaults to the type of template converted to a symbol
"""
function EmulationModel(
    ::Type{M},
    template::ProblemTemplate,
    sys::PSY.System,
    jump_model::Union{Nothing, JuMP.Model} = nothing;
    kwargs...,
) where {M <: EmulationProblem}
    return EmulationModel{M}(template, sys, jump_model; kwargs...)
end

function EmulationModel(
    template::ProblemTemplate,
    sys::PSY.System,
    jump_model::Union{Nothing, JuMP.Model} = nothing;
    kwargs...,
)
    return EmulationModel{GenericEmulationProblem}(template, sys, jump_model; kwargs...)
end

# """
# EmulationModel(filename::AbstractString)
#
# Construct an EmulationProblem from a serialized file.
#
# # Arguments
# - `filename::AbstractString`: path to serialized file
# - `jump_model::Union{Nothing, JuMP.Model}` = nothing: The JuMP model does not get
#    serialized. Callers should pass whatever they passed to the original problem.
# - `optimizer::Union{Nothing,MOI.OptimizerWithAttributes}` = nothing: The optimizer does
#    not get serialized. Callers should pass whatever they passed to the original problem.
# - `system::Union{Nothing, PSY.System}`: Optionally, the system used for the model.
#    If nothing and sys_to_file was set to true when the model was created, the system will
#    be deserialized from a file.
# """
# function EmulationModel(
#     filename::AbstractString;
#     jump_model::Union{Nothing, JuMP.Model} = nothing,
#     optimizer::Union{Nothing, MOI.OptimizerWithAttributes} = nothing,
#     system::Union{Nothing, PSY.System} = nothing,
# )
#     return deserialize_problem(
#         EmulationModel,
#         filename;
#         jump_model = jump_model,
#         optimizer = optimizer,
#         system = system,
#     )
# end

function get_current_time(model::EmulationModel)
    execution_count = get_internal(model).execution_count
    initial_time = get_initial_time(model)
    resolution = get_resolution(model.internal.store_parameters)
    return initial_time + resolution * execution_count
end

function model_store_params_init!(model::EmulationModel)
    num_executions = get_executions(model)
    system = get_system(model)
    interval = resolution = PSY.get_time_series_resolution(system)
    # This field is probably not needed for Emulation
    # end_of_interval_step = get_end_of_interval_step(get_internal(model))
    base_power = PSY.get_base_power(system)
    sys_uuid = IS.get_uuid(system)
    model.internal.store_parameters = ModelStoreParams(
        num_executions,
        1,
        interval,
        resolution,
        -1, #end_of_interval_step
        base_power,
        sys_uuid,
        get_metadata(get_optimization_container(model)),
    )
end

function model_store_init!(model::EmulationModel)
    # TODO DT: style of function names: verb_noun or noun_verb?
    model_store_params_init!(model)
    initialize_storage!(
        model.store,
        get_optimization_container(model),
        model.internal.store_parameters,
    )
    return
end

function build_pre_step!(model::EmulationModel)
    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Build pre-step" begin
        if !is_empty(model)
            @info "EmulationProblem status not BuildStatus.EMPTY. Resetting"
            reset!(model)
        end
        set_status!(model, BuildStatus.IN_PROGRESS)
    end
    return
end

# TODO DT: should this be called build_impl!
# Note that run! calls run_impl!
function _build!(model::EmulationModel{<:EmulationProblem}, serialize::Bool)
    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Problem $(get_name(model))" begin
        try
            build_pre_step!(model)
            # TODO DT: Why is this called problem build?
            problem_build!(model)
            model_store_init!(model)
            # serialize && serialize_problem(model)
            # serialize && serialize_optimization_model(model)
            serialize_metadata!(
                get_optimization_container(model),
                get_output_dir(model),
                get_name(model),
            )
            set_status!(model, BuildStatus.BUILT)
            log_values(get_settings(model))
            !built_for_recurrent_solves(model) && @info "\n$(BUILD_PROBLEMS_TIMER)\n"
        catch e
            set_status!(model, BuildStatus.FAILED)
            bt = catch_backtrace()
            @error "Emulation Problem Build Failed" exception = e, bt
        end
    end
    return get_status(model)
end

"""Implementation of build for any EmulationProblem"""
function build!(
    model::EmulationModel{<:EmulationProblem};
    executions = 1,
    output_dir::String,
    console_level = Logging.Error,
    file_level = Logging.Info,
    disable_timer_outputs = false,
    serialize = true,
)
    mkpath(output_dir)
    set_output_dir!(model, output_dir)
    set_console_level!(model, console_level)
    set_file_level!(model, file_level)
    TimerOutputs.reset_timer!(BUILD_PROBLEMS_TIMER)
    disable_timer_outputs && TimerOutputs.disable_timer!(BUILD_PROBLEMS_TIMER)
    logger = configure_logging(model.internal, "w")
    try
        Logging.with_logger(logger) do
            set_executions!(model, executions)
            return _build!(model, serialize)
        end
    finally
        close(logger)
    end
end

"""
Default implementation of build method for Emulation Problems for models conforming with  DecisionProblem specification. Overload this function to implement a custom build method
"""
function problem_build!(model::EmulationModel{<:EmulationProblem})
    @info "Initializing Optimization Container for EmulationModel"

    container = get_optimization_container(model)
    system = get_system(model)
    optimization_container_init!(
        container,
        get_network_formulation(get_template(model)),
        system,
    )
    # Temporary while are able to switch from PJ to POI
    container.built_for_recurrent_solves = true
    build_impl!(container, get_template(model), system)
end

function reset!(model::EmulationModel{<:EmulationProblem})
    if built_for_recurrent_solves(model)
        set_execution_count!(model, 0)
    end
    container = OptimizationContainer(
        get_system(model),
        get_settings(model),
        nothing,
        PSY.SingleTimeSeries,
    )
    model.internal.container = container
    empty_time_series_cache!(model)
    set_status!(model, BuildStatus.EMPTY)
    return
end

function serialize_optimization_model(model::EmulationModel{<:EmulationProblem})
    problem_name = "$(get_name(model))_EmulationModel"
    json_file_name = "$(problem_name).json"
    json_file_name = joinpath(get_output_dir(model), json_file_name)
    serialize_optimization_model(get_optimization_container(model), json_file_name)
end

function calculate_aux_variables!(model::EmulationModel)
    container = get_optimization_container(model)
    system = get_system(model)
    aux_vars = get_aux_variables(container)
    for key in keys(aux_vars)
        calculate_aux_variable_value!(container, key, system)
    end
    return
end

function calculate_dual_variables!(model::EmulationModel)
    container = get_optimization_container(model)
    system = get_system(model)
    duals_vars = get_duals(container)
    for key in keys(duals_vars)
        _calculate_dual_variable_value!(container, key, system)
    end
    return
end

"""
The one step solution method for the emulation model. Any Custom EmulationModel
needs to reimplement this method. This method is called by run! and execute!.
"""
function one_step_solve!(model::EmulationModel)
    jump_model = get_jump_model(model)
    JuMP.optimize!(jump_model)
    model_status = JuMP.primal_status(jump_model)
    if model_status != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
        error("Optimizer returned $model_status")
    else
        calculate_aux_variables!(model)
        calculate_dual_variables!(model)
    end
end

function update_model!(model::EmulationModel)
    for key in keys(get_parameters(model))
        update_parameter_values!(model, key)
    end
    #for key in keys(get_initial_constraints(model))
    #    update_initial_conditions!(model, key)
    #end
    return
end

function run_impl(
    model::EmulationModel;
    optimizer = nothing,
    enable_progress_bar = _PROGRESS_METER_ENABLED,
)
    set_run_status!(model, _pre_solve_model_checks(model, optimizer))
    internal = get_internal(model)
    # Temporary check. Needs better way to manage re-runs of the same model
    if internal.execution_count > 0
        error("Call build! again")
    end

    try
        prog_bar =
            ProgressMeter.Progress(internal.executions; enabled = enable_progress_bar)
        for execution in 1:(internal.executions)
            timed_log = get_solve_timed_log(model)
            _,
            timed_log[:timed_solve_time],
            timed_log[:solve_bytes_alloc],
            timed_log[:sec_in_gc] = @timed one_step_solve!(model)
            write_results!(model, execution)
            advance_execution_count!(model)
            update_model!(model)
            ProgressMeter.update!(
                prog_bar,
                get_execution_count(model);
                showvalues = [(:Execution, execution)],
            )
        end
    catch e
        @error "Emulation Problem Run failed" exception = (e, catch_backtrace())
        set_run_status!(model, RunStatus.FAILED)
        return get_run_status(model)
    finally
        set_run_status!(model, RunStatus.SUCCESSFUL)
    end
    return get_run_status(model)
end

"""
Default run method the Emulation model for a single instance. Solves problems
    that conform to the requirements of EmulationModel{<: EmulationProblem}

# Arguments
- `model::EmulationModel = model`: Emulation model
- `optimizer::MOI.OptimizerWithAttributes`: The optimizer that is used to solve the model
- `executions::Int`: Number of executions for the emulator run
- `enable_progress_bar::Bool`: Enables/Disable progress bar printing

# Examples
```julia
status = run!(model; optimizer = GLPK.Optimizer, executions = 10)
```
"""
function run!(model::EmulationModel{<:EmulationProblem}; kwargs...)
    status = run_impl(model; kwargs...)
    set_run_status!(model, status)
    return status
end

"""
Default solve method for an Emulation model used inside of a Simulation. Solves problems that conform to the requirements of EmulationModel{<: EmulationProblem}

# Arguments
- `step::Int`: Simulation Step
- `model::EmulationModel`: Emulation model
- `start_time::Dates.DateTime`: Initial Time of the simulation step in Simulation time.
- `store::SimulationStore`: Simulation output store
"""
function run!(
    step::Int,
    model::EmulationModel{<:EmulationProblem},
    start_time::Dates.DateTime,
    store::SimulationStore,
)
    # Initialize the InMemorySimulationStore
    solve_status = run!(model)
    if solve_status == RunStatus.SUCCESSFUL
        write_problem_results!(step, model, start_time, store)
        advance_execution_count!(model)
    end

    return solve_status
end

list_aux_variable_keys(x::EmulationModel) =
    list_keys(get_store(x), STORE_CONTAINER_AUX_VARIABLES)
list_aux_variable_names(x::EmulationModel) = _list_names(x, STORE_CONTAINER_AUX_VARIABLES)
list_variable_keys(x::EmulationModel) = list_keys(get_store(x), STORE_CONTAINER_VARIABLES)
list_variable_names(x::EmulationModel) = _list_names(x, STORE_CONTAINER_VARIABLES)
list_parameter_keys(x::EmulationModel) = list_keys(get_store(x), STORE_CONTAINER_PARAMETERS)
list_parameter_names(x::EmulationModel) = _list_names(x, STORE_CONTAINER_PARAMETERS)
list_dual_keys(x::EmulationModel) = list_keys(get_store(x), STORE_CONTAINER_DUALS)
list_dual_names(x::EmulationModel) = _list_names(x, STORE_CONTAINER_DUALS)

function _list_names(model::EmulationModel, container_type)
    return encode_keys_as_strings(list_keys(get_store(model), container_type))
end

function write_results!(model::EmulationModel, execution)
    store = get_store(model)
    container = get_optimization_container(model)

    _write_model_dual_results!(store, container, execution)
    _write_model_parameter_results!(store, container, execution)
    _write_model_variable_results!(store, container, execution)
    _write_model_aux_variable_results!(store, container, execution)
    write_optimizer_stats!(store, OptimizerStats(model, 1), execution)
end

function read_dual(model::EmulationModel, key::ConstraintKey)
    return read_results(get_store(model), STORE_CONTAINER_DUALS, key)
end

function read_parameter(model::EmulationModel, key::ParameterKey)
    return read_results(get_store(model), STORE_CONTAINER_PARAMETERS, key)
end

function read_aux_variable(model::EmulationModel, key::VariableKey)
    return read_results(get_store(model), STORE_CONTAINER_AUX_VARIABLES, key)
end

function read_variable(model::EmulationModel, key::VariableKey)
    return read_results(get_store(model), STORE_CONTAINER_VARIABLES, key)
end

function _write_model_dual_results!(store, container, execution)
    for (key, dual) in get_duals(container)
        write_result!(store, STORE_CONTAINER_DUALS, key, execution, dual)
    end
end

function _write_model_parameter_results!(store, container, execution)
    parameters = get_parameters(container)
    (isnothing(parameters) || isempty(parameters)) && return
    horizon = 1

    for (key, parameter) in parameters
        name = encode_key(key)
        param_array = get_parameter_array(parameter)
        multiplier_array = get_multiplier_array(parameter)
        @assert_op length(axes(param_array)) == 2
        num_columns = size(param_array)[1]
        data = Array{Float64}(undef, horizon, num_columns)
        for r_ix in param_array.axes[2], (c_ix, name) in enumerate(param_array.axes[1])
            val1 = _jump_value(param_array[name, r_ix])
            val2 = multiplier_array[name, r_ix]
            data[r_ix, c_ix] = val1 * val2
        end

        write_result!(
            store,
            STORE_CONTAINER_PARAMETERS,
            key,
            execution,
            data,
            param_array.axes[1],
        )
    end
end

function _write_model_variable_results!(store, container, execution)
    for (key, variable) in get_variables(container)
        write_result!(store, STORE_CONTAINER_VARIABLES, key, execution, variable)
    end
end

function _write_model_aux_variable_results!(store, container, execution)
    for (key, variable) in get_aux_variables(container)
        write_result!(store, STORE_CONTAINER_AUX_VARIABLES, key, execution, variable)
    end
end

read_optimizer_stats(model::EmulationModel) = read_optimizer_stats(get_store(model))
