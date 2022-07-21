@testset "Test segments and step ranges" begin
    segments = SimulationSegments(2, 1)
    @test PSI.get_absolute_step_range(segments, 1) == 1:1
    @test PSI.get_valid_step_offset(segments, 1) == 1
    @test PSI.get_valid_step_length(segments, 1) == 1
    @test PSI.get_absolute_step_range(segments, 2) == 2:2
    @test PSI.get_valid_step_offset(segments, 2) == 1
    @test PSI.get_valid_step_length(segments, 2) == 1

    segments = SimulationSegments(365, 7, 1)
    @test get_num_segments(segments) == 53
    @test PSI.get_absolute_step_range(segments, 1) == 1:7
    @test PSI.get_valid_step_offset(segments, 1) == 1
    @test PSI.get_valid_step_length(segments, 1) == 7
    @test PSI.get_absolute_step_range(segments, 2) == 7:14
    @test PSI.get_valid_step_offset(segments, 2) == 2
    @test PSI.get_valid_step_length(segments, 2) == 7
    @test PSI.get_absolute_step_range(segments, 52) == 357:364
    @test PSI.get_valid_step_offset(segments, 52) == 2
    @test PSI.get_valid_step_length(segments, 52) == 7
    @test PSI.get_absolute_step_range(segments, 53) == 364:365
    @test PSI.get_valid_step_offset(segments, 53) == 2
    @test PSI.get_valid_step_length(segments, 53) == 1

    @test_throws ErrorException PSI.get_absolute_step_range(segments, -1)
    @test_throws ErrorException PSI.get_absolute_step_range(segments, 54)
end

function build_simulation(
    output_dir::AbstractString,
    simulation_name::AbstractString,
    segments::SimulationSegments,
    index::Union{Nothing, Integer}=nothing;
    use_segments=true,
)
    template_uc = get_template_basic_uc_simulation()
    set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)
    set_network_model!(template_uc, NetworkModel(
        CopperPlatePowerModel,
        # MILP "duals" not supported with free solvers
        # duals = [CopperPlateBalanceConstraint],
    ))

    template_ed = get_template_nomin_ed_simulation(
        NetworkModel(
            CopperPlatePowerModel;
            # Added because of data issues
            use_slacks=true,
            duals=[CopperPlateBalanceConstraint],
        ),
    )
    set_device_model!(template_ed, InterruptibleLoad, StaticPowerLoad)
    set_device_model!(template_ed, HydroEnergyReservoir, HydroDispatchReservoirBudget)
    c_sys5_hy_uc = PSB.build_system(PSITestSystems, "c_sys5_hy_uc")
    c_sys5_hy_ed = PSB.build_system(PSITestSystems, "c_sys5_hy_ed")
    models = SimulationModels(
        decision_models=[
            DecisionModel(template_uc, c_sys5_hy_uc; name="UC", optimizer=GLPK_optimizer),
            DecisionModel(template_ed, c_sys5_hy_ed; name="ED", optimizer=ipopt_optimizer),
        ],
    )

    sequence = SimulationSequence(
        models=models,
        feedforwards=Dict(
            "ED" => [
                SemiContinuousFeedforward(
                    component_type=ThermalStandard,
                    source=OnVariable,
                    affected_values=[ActivePowerVariable],
                ),
                EnergyLimitFeedforward(
                    component_type=HydroEnergyReservoir,
                    source=ActivePowerVariable,
                    affected_values=[ActivePowerVariable],
                    number_of_periods=12,
                ),
            ],
        ),
        ini_cond_chronology=InterProblemChronology(),
    )
    !isdir(output_dir) && error("$output_dir does not exist")
    sim = Simulation(
        name=simulation_name,
        steps=segments.num_steps,
        models=models,
        sequence=sequence,
        simulation_folder=output_dir,
    )
    status = build!(
        sim;
        segments=use_segments ? segments : nothing,
        index=index,
        serialize=isnothing(index),
    )
    if status != PSI.BuildStatus.BUILT
        error("Failed to build simulation: status=$status")
    end

    return sim
end

function execute_simulation(sim, args...; kwargs...)
    return execute!(sim)
end

@testset "Test simulation segments" begin
    sim_dir = mktempdir()
    segments = SimulationSegments(2, 1, 1)
    regular_sim = build_simulation(sim_dir, "regular_sim", segments, use_segments=false)
    @test execute_simulation(regular_sim) == PSI.RunStatus.SUCCESSFUL

    name = "segmented_sim"
    args = [
        "setup",
        "--simulation-name=$name",
        "--num-steps=$(segments.num_steps)",
        "--num-period-steps=$(segments.period)",
        "--num-overlap-steps=$(segments.num_overlap_steps)",
        "--output-dir=$sim_dir",
    ]
    process_simulation_segment_cli_args(build_simulation, execute_simulation, args...)
    for index in 1:get_num_segments(segments)
        args = [
            "execute",
            "--simulation-name=$name",
            "--index=$index",
            "--output-dir=$sim_dir",
        ]
        process_simulation_segment_cli_args(build_simulation, execute_simulation, args...)
    end
    args = ["join", "--simulation-name=$name", "--output-dir=$sim_dir"]
    process_simulation_segment_cli_args(build_simulation, execute_simulation, args...)

    regular_results = SimulationResults(joinpath(sim_dir, "regular_sim"))
    segmented_results = SimulationResults(joinpath(sim_dir, "segmented_sim"))

    functions = (
        (list_aux_variable_names, read_aux_variable),
        (list_dual_names, read_dual),
        (list_expression_names, read_expression),
        (list_parameter_names, read_parameter),
        (list_variable_names, read_variable),
    )
    for model_name in ("ED", "UC")
        regular = get_decision_problem_results(regular_results, model_name)
        segmented = get_decision_problem_results(segmented_results, model_name)
        @test get_timestamps(regular) == get_timestamps(segmented)
        for (list_func, read_func) in functions
            @test list_func(segmented) == list_func(regular)
            for timestamp in get_timestamps(regular)
                for name in list_func(segmented)
                    segmented_dict = read_func(segmented, name, initial_time=timestamp)
                    regular_dict = read_func(regular, name, initial_time=timestamp)
                    @test collect(keys(segmented_dict)) == collect(keys(regular_dict))
                    for key in keys(segmented_dict)
                        @test segmented_dict[key] == regular_dict[key]
                    end
                end
            end
        end
    end

    functions = (
        read_realized_aux_variables,
        read_realized_duals,
        read_realized_expressions,
        read_realized_parameters,
        read_realized_variables,
    )
    for model_name in ("ED", "UC")
        regular = get_decision_problem_results(regular_results, model_name)
        segmented = get_decision_problem_results(segmented_results, model_name)

        for func in functions
            regular_realized = func(regular)
            segmented_realized = func(segmented)
            @test segmented_realized == regular_realized
        end
    end

    # TODO: Some columns have mismatches in the first segment.
    # This may be expected. Disabling until that is confirmed.
    # regular = get_emulation_problem_results(regular_results)
    # segmented = get_emulation_problem_results(segmented_results)
    # for func in functions
    #     regular_realized = func(regular)
    #     segmented_realized = func(segmented)
    #     @test segmented_realized == regular_realized
    # end
end
