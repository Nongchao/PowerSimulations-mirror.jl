function build_simulation(
    output_dir::AbstractString,
    simulation_name::AbstractString,
    segments::SimulationSegments,
    index::Union{Nothing, Integer}=nothing,
    use_splits=false,
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
    if use_splits
        status = build!(sim; segments=segments, index=index, serialize=isnothing(index))
    else
        status = build!(sim)
    end
    if status != PSI.BuildStatus.BUILT
        error("Failed to build simulation: status=$status")
    end

    return sim
end

function execute_simulation(sim, args...; kwargs...)
    status = execute!(sim)
    if status != PSI.RunStatus.SUCCESSFUL
        error("Simulation failed to execute: status=$status")
    end
    return status
end

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

# @testset "Test simulation segments" begin
#     sim_dir = mktempdir()
#     sim_non_split = build_simulation(sim_dir, "non_split_sim")    
#     @test execute_simulation(sim_non_split) == PSI.RunStatus.SUCCESSFUL
# end

function main()
    process_simulation_segment_cli_args(build_simulation, execute_simulation, ARGS...)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
