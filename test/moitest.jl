push!(Base.LOAD_PATH,joinpath(dirname(@__FILE__),"..",".."))

using ProxSDP, MathOptInterface, Test, LinearAlgebra, Random, SparseArrays, DelimitedFiles

const MOI = MathOptInterface
const MOIT = MOI.Test
const MOIB = MOI.Bridges
const MOIU = MOI.Utilities

MOIU.@model ProxSDPModelData () (MOI.EqualTo, MOI.GreaterThan, MOI.LessThan) (MOI.Zeros, MOI.Nonnegatives, MOI.Nonpositives, MOI.SecondOrderCone, MOI.PositiveSemidefiniteConeTriangle) () (MOI.SingleVariable,) (MOI.ScalarAffineFunction,) (MOI.VectorOfVariables,) (MOI.VectorAffineFunction,)

const optimizer = MOIU.CachingOptimizer(ProxSDPModelData{Float64}(), ProxSDP.Optimizer(tol_primal = 1e-5, tol_dual = 1e-5))
const optimizer_lin = MOIU.CachingOptimizer(ProxSDPModelData{Float64}(), ProxSDP.Optimizer(tol_primal = 1e-5, tol_dual = 1e-5))
const optimizer_lin_hd = MOIU.CachingOptimizer(ProxSDPModelData{Float64}(), ProxSDP.Optimizer(tol_primal = 1e-5, tol_dual = 1e-5))
const optimizer3 = MOIU.CachingOptimizer(ProxSDPModelData{Float64}(), ProxSDP.Optimizer(log_freq = 1000, log_verbose = false, tol_primal = 1e-5, tol_dual = 1e-5))
const optimizer_log = MOIU.CachingOptimizer(ProxSDPModelData{Float64}(), ProxSDP.Optimizer(log_freq = 10, log_verbose = true, tol_primal = 1e-5, tol_dual = 1e-5))
const optimizer_unsupportedarg = MOIU.CachingOptimizer(ProxSDPModelData{Float64}(), ProxSDP.Optimizer(unsupportedarg = 10))
const optimizer_maxiter = MOIU.CachingOptimizer(ProxSDPModelData{Float64}(), ProxSDP.Optimizer(max_iter = 1, log_verbose = true))
const optimizer_timelimit = MOIU.CachingOptimizer(ProxSDPModelData{Float64}(), ProxSDP.Optimizer(time_limit = 0.0001, log_verbose = true))

const config = MOIT.TestConfig(atol=1e-3, rtol=1e-3)
const config_conic = MOIT.TestConfig(atol=1e-3, rtol=1e-3, duals = false)

@testset "SolverName" begin
    @test MOI.get(optimizer, MOI.SolverName()) == "ProxSDP"
end

@testset "Unit" begin
    MOIT.unittest(MOIB.SplitInterval{Float64}(optimizer_lin), config,[
        # Quadratic functions are not supported
        "solve_qcp_edge_cases", "solve_qp_edge_cases",
        # Integer and ZeroOne sets are not supported
        "solve_integer_edge_cases", "solve_objbound_edge_cases"
        ]
    )
end

# @testset "MOI Continuous Linear" begin
#     MOIT.contlineartest(MOIB.SplitInterval{Float64}(optimizer_lin), config, [
#         # infeasible/unbounded
#         "linear8a", "linear8b", "linear8c", "linear12", 
#         # linear10 is poorly conditioned
#         "linear10",
#         # linear9 is requires precision
#         "linear9",
#         # primalstart not accepted
#         "partial_start"
#         ]
#     )
#     # MOIT.linear9test(MOIB.SplitInterval{Float64}(optimizer_lin_hd), config)
# end

@testset "MOI Continuous Conic" begin
    MOIT.contconictest(optimizer_lin, config_conic, [
        # bridge
        "rootdet","geomean",
        # affine in cone
        "psdt1f","psdt0f","soc2p", "soc2n", "rsoc","soc1f",
        # square psd
        "psds", "rootdets",
        # exp cone
        "logdet", "exp",
        # infeasible/unbounded
        "lin3", "lin4", "soc3", "rotatedsoc2", "psdt2"
        ]
    )
end

@testset "MOI Continuous Conic with VectorSlack" begin
    MOIT.contconictest(MOIB.VectorSlack{Float64}(optimizer_lin_hd), config_conic, [
        # bridge
        "rootdet","geomean",
        # affine in cone
        "rsoc",
        # square psd
        "psds", "rootdets",
        # exp cone
        "logdet", "exp",
        # infeasible/unbounded
        "lin3", "lin4", "soc3", "rotatedsoc2", "psdt2"
        ]
    )
end

@testset "MOI Continuous Conic with FullBridge" begin
    MOIT.contconictest(MOIB.full_bridge_optimizer(optimizer_lin_hd, Float64), config_conic, [
        # bridge: needs to add set in VectorSlack bridge MOI
        "rootdet",
        # exp cone
        "logdet", "exp",
        # infeasible/unbounded
        "lin3", "lin4", "soc3", "rotatedsoc2", "psdt2"
        ]
    )
end

@testset "Simple LP" begin

    MOI.empty!(optimizer)
    @test MOI.is_empty(optimizer)

    # add 10 variables - only diagonal is relevant
    X = MOI.add_variables(optimizer, 2)

    # add sdp constraints - only ensuring positivenesse of the diagonal
    vov = MOI.VectorOfVariables(X)

    c1 = MOI.add_constraint(optimizer, 
        MOI.ScalarAffineFunction([
            MOI.ScalarAffineTerm(2.0, X[1]),
            MOI.ScalarAffineTerm(1.0, X[2])
        ], 0.0), MOI.EqualTo(4.0))

    c2 = MOI.add_constraint(optimizer, 
        MOI.ScalarAffineFunction([
            MOI.ScalarAffineTerm(1.0, X[1]),
            MOI.ScalarAffineTerm(2.0, X[2])
        ], 0.0), MOI.EqualTo(4.0))

    b1 = MOI.add_constraint(optimizer, 
        MOI.ScalarAffineFunction([
            MOI.ScalarAffineTerm(1.0, X[1])
        ], 0.0), MOI.GreaterThan(0.0))

    b2 = MOI.add_constraint(optimizer, 
        MOI.ScalarAffineFunction([
            MOI.ScalarAffineTerm(1.0, X[2])
        ], 0.0), MOI.GreaterThan(0.0))

    MOI.set(optimizer, 
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), 
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([-4.0, -3.0], [X[1], X[2]]), 0.0)
        )
    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.optimize!(optimizer)

    obj = MOI.get(optimizer, MOI.ObjectiveValue())

    @test obj ≈ -9.33333 atol = 1e-2

    Xr = MOI.get(optimizer, MOI.VariablePrimal(), X)

    @test Xr ≈ [1.3333, 1.3333] atol = 1e-2

end

@testset "Simple LP with 2 1D SDP" begin

    MOI.empty!(optimizer)
    @test MOI.is_empty(optimizer)

    # add 10 variables - only diagonal is relevant
    X = MOI.add_variables(optimizer, 2)

    # add sdp constraints - only ensuring positivenesse of the diagonal
    vov = MOI.VectorOfVariables(X)

    c1 = MOI.add_constraint(optimizer, 
        MOI.ScalarAffineFunction([
            MOI.ScalarAffineTerm(2.0, X[1]),
            MOI.ScalarAffineTerm(1.0, X[2])
        ], 0.0), MOI.EqualTo(4.0))

    c2 = MOI.add_constraint(optimizer, 
        MOI.ScalarAffineFunction([
            MOI.ScalarAffineTerm(1.0, X[1]),
            MOI.ScalarAffineTerm(2.0, X[2])
        ], 0.0), MOI.EqualTo(4.0))

    b1 = MOI.add_constraint(optimizer, 
        MOI.VectorOfVariables([X[1]]), MOI.PositiveSemidefiniteConeTriangle(1))

    b2 = MOI.add_constraint(optimizer, 
        MOI.VectorOfVariables([X[2]]), MOI.PositiveSemidefiniteConeTriangle(1))

    MOI.set(optimizer, 
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), 
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([-4.0, -3.0], [X[1], X[2]]), 0.0)
        )
    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.optimize!(optimizer)

    obj = MOI.get(optimizer, MOI.ObjectiveValue())

    @test obj ≈ -9.33333 atol = 1e-2

    Xr = MOI.get(optimizer, MOI.VariablePrimal(), X)

    @test Xr ≈ [1.3333, 1.3333] atol = 1e-2

end

@testset "LP in SDP EQ form" begin

    MOI.empty!(optimizer)
    @test MOI.is_empty(optimizer)

    # add 10 variables - only diagonal is relevant
    X = MOI.add_variables(optimizer, 10)

    # add sdp constraints - only ensuring positivenesse of the diagonal
    vov = MOI.VectorOfVariables(X)
    cX = MOI.add_constraint(optimizer, vov, MOI.PositiveSemidefiniteConeTriangle(4))

    c1 = MOI.add_constraint(optimizer, 
        MOI.ScalarAffineFunction([
            MOI.ScalarAffineTerm(2.0, X[1]),
            MOI.ScalarAffineTerm(1.0, X[3]),
            MOI.ScalarAffineTerm(1.0, X[6])
        ], 0.0), MOI.EqualTo(4.0))

    c2 = MOI.add_constraint(optimizer, 
        MOI.ScalarAffineFunction([
            MOI.ScalarAffineTerm(1.0, X[1]),
            MOI.ScalarAffineTerm(2.0, X[3]),
            MOI.ScalarAffineTerm(1.0, X[10])
        ], 0.0), MOI.EqualTo(4.0))

    MOI.set(optimizer, 
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), 
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([-4.0, -3.0], [X[1], X[3]]), 0.0)
        )
    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.optimize!(optimizer)

    obj = MOI.get(optimizer, MOI.ObjectiveValue())

    @test obj ≈ -9.33333 atol = 1e-2

    Xr = MOI.get(optimizer, MOI.VariablePrimal(), X)

    @test Xr ≈ [1.3333, .0, 1.3333, .0, .0, .0, .0, .0, .0, .0] atol = 1e-2

end

@testset "LP in SDP INEQ form" begin

    MOI.empty!(optimizer)
    @test MOI.is_empty(optimizer)

    # add 10 variables - only diagonal is relevant
    X = MOI.add_variables(optimizer, 3)

    # add sdp constraints - only ensuring positivenesse of the diagonal
    vov = MOI.VectorOfVariables(X)
    cX = MOI.add_constraint(optimizer, vov, MOI.PositiveSemidefiniteConeTriangle(2))

    c1 = MOI.add_constraint(optimizer, 
        MOI.ScalarAffineFunction([
            MOI.ScalarAffineTerm(2.0, X[1]),
            MOI.ScalarAffineTerm(1.0, X[3]),
        ], 0.0), MOI.LessThan(4.0))

    c2 = MOI.add_constraint(optimizer, 
        MOI.ScalarAffineFunction([
            MOI.ScalarAffineTerm(1.0, X[1]),
            MOI.ScalarAffineTerm(2.0, X[3]),
        ], 0.0), MOI.LessThan(4.0))

    MOI.set(optimizer, 
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), 
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([4.0, 3.0], [X[1], X[3]]), 0.0)
        )
    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    MOI.optimize!(optimizer)

    obj = MOI.get(optimizer, MOI.ObjectiveValue())

    @test obj ≈ 9.33333 atol = 1e-2

    Xr = MOI.get(optimizer, MOI.VariablePrimal(), X)

    @test Xr ≈ [1.3333, .0, 1.3333] atol = 1e-2

    c1_d = MOI.get(optimizer, MOI.ConstraintDual(), c1)
    c2_d = MOI.get(optimizer, MOI.ConstraintDual(), c2)

    # SDP duasl error
    @test_throws ErrorException c2_d = MOI.get(optimizer, MOI.ConstraintDual(), cX)

end

@testset "SDP from MOI" begin
    # min X[1,1] + X[2,2]    max y
    #     X[2,1] = 1         [0   y/2     [ 1  0
    #                         y/2 0    <=   0  1]
    #     X >= 0              y free
    # Optimal solution:
    #
    #     ⎛ 1   1 ⎞
    # X = ⎜       ⎟           y = 2
    #     ⎝ 1   1 ⎠
    MOI.empty!(optimizer)
    @test MOI.is_empty(optimizer)

    X = MOI.add_variables(optimizer, 3)

    vov = MOI.VectorOfVariables(X)
    cX = MOI.add_constraint(optimizer, vov, MOI.PositiveSemidefiniteConeTriangle(2))

    c = MOI.add_constraint(optimizer, MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, X[2])], 0.0), MOI.EqualTo(1.0))

    MOI.set(optimizer, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(1.0, [X[1], X[end]]), 0.0))

    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.optimize!(optimizer)

    @test MOI.get(optimizer, MOI.TerminationStatus()) == MOI.OPTIMAL

    @test MOI.get(optimizer, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
    @test MOI.get(optimizer, MOI.DualStatus()) == MOI.FEASIBLE_POINT

    @test MOI.get(optimizer, MOI.ObjectiveValue()) ≈ 2 atol=1e-2

    Xv = ones(3)
    @test MOI.get(optimizer, MOI.VariablePrimal(), X) ≈ Xv atol=1e-2
    # @test MOI.get(optimizer, MOI.ConstraintPrimal(), cX) ≈ Xv atol=1e-2

    # @test MOI.get(optimizer, MOI.ConstraintDual(), c) ≈ 2 atol=1e-2
    # @show MOI.get(optimizer, MOI.ConstraintDual(), c)

end

@testset "Double SDP from MOI" begin
    # solve simultaneously two of these:
    # min X[1,1] + X[2,2]    max y
    #     X[2,1] = 1         [0   y/2     [ 1  0
    #                         y/2 0    <=   0  1]
    #     X >= 0              y free
    # Optimal solution:
    #
    #     ⎛ 1   1 ⎞
    # X = ⎜       ⎟           y = 2
    #     ⎝ 1   1 ⎠
    MOI.empty!(optimizer)
    @test MOI.is_empty(optimizer)

    X = MOI.add_variables(optimizer, 3)
    Y = MOI.add_variables(optimizer, 3)

    vov = MOI.VectorOfVariables(X)
    vov2 = MOI.VectorOfVariables(Y)
    cX = MOI.add_constraint(optimizer, vov, MOI.PositiveSemidefiniteConeTriangle(2))
    cY = MOI.add_constraint(optimizer, vov2, MOI.PositiveSemidefiniteConeTriangle(2))

    c = MOI.add_constraint(optimizer, MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, X[2])], 0.0), MOI.EqualTo(1.0))
    c2 = MOI.add_constraint(optimizer, MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, Y[2])], 0.0), MOI.EqualTo(1.0))

    MOI.set(optimizer, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(1.0, [X[1], X[end], Y[1], Y[end]]), 0.0))

    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.optimize!(optimizer)

    @test MOI.get(optimizer, MOI.TerminationStatus()) == MOI.OPTIMAL

    @test MOI.get(optimizer, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
    @test MOI.get(optimizer, MOI.DualStatus()) == MOI.FEASIBLE_POINT

    @test MOI.get(optimizer, MOI.ObjectiveValue()) ≈ 2*2 atol=1e-2

    Xv = ones(3)
    @test MOI.get(optimizer, MOI.VariablePrimal(), X) ≈ Xv atol=1e-2
    Yv = ones(3)
    @test MOI.get(optimizer, MOI.VariablePrimal(), Y) ≈ Yv atol=1e-2
    # @test MOI.get(optimizer, MOI.ConstraintPrimal(), cX) ≈ Xv atol=1e-2

    # @test MOI.get(optimizer, MOI.ConstraintDual(), c) ≈ 2 atol=1e-2
    # @show MOI.get(optimizer, MOI.ConstraintDual(), c)

end

@testset "SDP with duplicates from MOI" begin

    MOI.empty!(optimizer)
    @test MOI.is_empty(optimizer)

    x = MOI.add_variable(optimizer)
    X = [x, x, x]

    vov = MOI.VectorOfVariables(X)
    cX = MOI.add_constraint(optimizer, vov, MOI.PositiveSemidefiniteConeTriangle(2))

    c = MOI.add_constraint(optimizer, MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, X[2])], 0.0), MOI.EqualTo(1.0))

    MOI.set(optimizer, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(1.0, [X[1], X[end]]), 0.0))

    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.optimize!(optimizer)

    @test MOI.get(optimizer, MOI.TerminationStatus()) == MOI.OPTIMAL

    @test MOI.get(optimizer, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
    @test MOI.get(optimizer, MOI.DualStatus()) == MOI.FEASIBLE_POINT

    @test MOI.get(optimizer, MOI.ObjectiveValue()) ≈ 2 atol=1e-2

    Xv = ones(3)
    @test MOI.get(optimizer, MOI.VariablePrimal(), X) ≈ Xv atol=1e-2
    # @test MOI.get(optimizer, MOI.ConstraintPrimal(), cX) ≈ Xv atol=1e-2

    # @test MOI.get(optimizer, MOI.ConstraintDual(), c) ≈ 2 atol=1e-2
    # @show MOI.get(optimizer, MOI.ConstraintDual(), c)

end

@testset "SDP from Wikipedia" begin
    # https://en.wikipedia.org/wiki/Semidefinite_programming
    MOI.empty!(optimizer)
    @test MOI.is_empty(optimizer)

    X = MOI.add_variables(optimizer, 6)

    vov = MOI.VectorOfVariables(X)
    cX = MOI.add_constraint(optimizer, vov, MOI.PositiveSemidefiniteConeTriangle(3))

    cd1 = MOI.add_constraint(optimizer, MOI.SingleVariable(X[1]), MOI.EqualTo(1.0))
    cd2 = MOI.add_constraint(optimizer, MOI.SingleVariable(X[3]), MOI.EqualTo(1.0))
    cd3 = MOI.add_constraint(optimizer, MOI.SingleVariable(X[6]), MOI.EqualTo(1.0))

    c12_ub = MOI.add_constraint(optimizer, MOI.SingleVariable(X[2]), MOI.LessThan(-0.1))
    c12_lb = MOI.add_constraint(optimizer, MOI.SingleVariable(X[2]), MOI.GreaterThan(-0.2))

    c23_ub = MOI.add_constraint(optimizer, MOI.SingleVariable(X[5]), MOI.LessThan(0.5))
    c23_lb = MOI.add_constraint(optimizer, MOI.SingleVariable(X[5]), MOI.GreaterThan(0.4))

    MOI.set(optimizer, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(1.0, [X[4]]), 0.0))

    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    MOI.optimize!(optimizer)

    obj = MOI.get(optimizer, MOI.ObjectiveValue())
    @test obj ≈ -0.978 atol=1e-2

    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MAX_SENSE)

    MOI.optimize!(optimizer)

    obj = MOI.get(optimizer, MOI.ObjectiveValue())
    @test obj ≈ 0.872 atol=1e-2

end

@testset "MIMO" begin

    Random.seed!(23)

    # Instance size
    n = 3
    m = 10 * n
    # Channel
    H = randn((m, n))
    # Gaussian noise
    v = randn((m, 1))
    # True signal
    s = rand([-1, 1], n)
    # Received signal
    sigma = 10.0
    y = H * s + sigma * v
    L = [hcat(H' * H, -H' * y); hcat(-y' * H, y' * y)]

    MOI.empty!(optimizer)
    @test MOI.is_empty(optimizer)

    nvars = ProxSDP.sympackedlen(n+1)

    X = MOI.add_variables(optimizer, nvars)

    for i in 1:nvars
        MOI.add_constraint(optimizer, MOI.SingleVariable(X[i]), MOI.LessThan(1.0))
        MOI.add_constraint(optimizer, MOI.SingleVariable(X[i]), MOI.GreaterThan(-1.0))
    end

    LinearAlgebra.symmetric_type(::Type{MOI.VariableIndex}) = MOI.VariableIndex
    LinearAlgebra.symmetric(v::MOI.VariableIndex, ::Symbol) = v
    LinearAlgebra.transpose(v::MOI.VariableIndex) = v
    Xsq = Matrix{MOI.VariableIndex}(undef, n+1,n+1)
    ProxSDP.ivech!(Xsq, X)
    Xsq = Symmetric(Xsq,:U)

    vov = MOI.VectorOfVariables(X)
    cX = MOI.add_constraint(optimizer, vov, MOI.PositiveSemidefiniteConeTriangle(n+1))


    for i in 1:n+1
        MOI.add_constraint(optimizer, MOI.SingleVariable(Xsq[i,i]), MOI.EqualTo(1.0))
    end

    objf_t = vec([MOI.ScalarAffineTerm(L[i,j], Xsq[i,j]) for i in 1:n+1, j in 1:n+1])
    MOI.set(optimizer, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(objf_t, 0.0))

    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    MOI.optimize!(optimizer)

    obj = MOI.get(optimizer, MOI.ObjectiveValue())

    Xsq_s = MOI.get.(optimizer, MOI.VariablePrimal(), Xsq)

    # for i in 1:n+1, j in 1:n+1
    #     @test 1.01> abs(Xsq_s[i,j]) > 0.99
    # end

end

@testset "MIMO Sizes" begin
    include("base_mimo.jl")
    include("moi_mimo.jl")
    for i in 2:5
        @testset "MIMO n = $(i)" begin 
            moi_mimo(optimizer, 123, i, test = true)
        end
    end
end

@testset "RANDSDP Sizes" begin
    include("base_randsdp.jl")
    include("moi_randsdp.jl")
    for n in 10:12, m in 10:12
        @testset "RANDSDP n=$n, m=$m" begin 
            moi_randsdp(optimizer, 123, n, m, test = true, atol = 1e-1)
        end
    end
end

# This problems are too large for Travis
# @testset "SDPLIB Sizes" begin
#     datapath = joinpath(dirname(@__FILE__), "data")
#     include("base_sdplib.jl")
#     include("moi_sdplib.jl")
#     @testset "EQPART" begin
#         moi_sdplib(optimizer, joinpath(datapath, "gpp124-1.dat-s"), test = true)
#         moi_sdplib(optimizer, joinpath(datapath, "gpp124-2.dat-s"), test = true)
#         moi_sdplib(optimizer, joinpath(datapath, "gpp124-3.dat-s"), test = true)
#         moi_sdplib(optimizer, joinpath(datapath, "gpp124-4.dat-s"), test = true)
#     end
#     @testset "MAX CUT" begin
#         moi_sdplib(optimizer, joinpath(datapath, "mcp124-1.dat-s"), test = true)
#         moi_sdplib(optimizer, joinpath(datapath, "mcp124-2.dat-s"), test = true)
#         moi_sdplib(optimizer, joinpath(datapath, "mcp124-3.dat-s"), test = true)
#         moi_sdplib(optimizer, joinpath(datapath, "mcp124-4.dat-s"), test = true)
#     end
# end

@testset "Sensor Localization" begin
    include("base_sensorloc.jl")
    include("moi_sensorloc.jl")
    for n in 20:5:30
        moi_sensorloc(optimizer, 0, n, test = true)
    end
end

@testset "Full eig" begin
    MOIT.psdt0vtest(MOIU.CachingOptimizer(ProxSDPModelData{Float64}(), ProxSDP.Optimizer(full_eig_decomp = true, tol_primal = 1e-4, tol_dual = 1e-4)), MOIT.TestConfig(atol=1e-3, rtol=1e-3, duals = false))
end

@testset "Print" begin
    MOIT.linear15test(MOIU.CachingOptimizer(ProxSDPModelData{Float64}(), ProxSDP.Optimizer(log_freq = 10, log_verbose = true, timer_verbose = true, tol_primal = 1e-4, tol_dual = 1e-4)), MOIT.TestConfig(atol=1e-3, rtol=1e-3))
end

@testset "Unsupported argument" begin
    @test_throws ErrorException MOI.optimize!(optimizer_unsupportedarg)
end

include("test_terminationstatus.jl")