
function moi_sensorloc(optimizer, seed, n; verbose = false, test = false)

    Random.seed!(seed)
    MOI.empty!(optimizer)
    if test
        @test MOI.is_empty(optimizer)
    end
    # Generate randomized problem data
    m, x_true, a, d, d_bar = sensorloc_data(seed, n)

    # Decision variable
    nvars = ProxSDP.sympackedlen(n + 2) 
    X = MOI.add_variables(optimizer, nvars)
    Xsq = Matrix{MOI.VariableIndex}(undef, n + 2, n + 2)
    ProxSDP.ivech!(Xsq, X)
    Xsq = Matrix(Symmetric(Xsq, :U))
    vov = MOI.VectorOfVariables(X)
    cX = MOI.add_constraint(optimizer, vov, MOI.PositiveSemidefiniteConeTriangle(n + 2))

    # Constraint with distances from anchors to sensors
    for k in 1:m
        for j in 1:n
            e = zeros(n, 1)
            e[j] = -1.0
            v = vcat(a[k], e)
            V = v * v'
            ctr_aff = vec([MOI.ScalarAffineTerm(V[i, j_], Xsq[i, j_]) for i in 1:n + 2, j_ in 1:n + 2])
            MOI.add_constraint(optimizer, MOI.ScalarAffineFunction(ctr_aff, 0.0), MOI.EqualTo(d_bar[k, j]^2))
        end
    end

    # Constraint with distances from sensors to sensors
    count, count_all = 0, 0
    for i in 1:n
        for j in 1:i - 1
            count_all += 1
            if rand() > 0.9
                count += 1
                e = zeros(n, 1)
                e[i] = 1.0
                e[j] = -1.0
                v = vcat(zeros(2, 1), e)
                V = v * v'
                ctr_aff = vec([MOI.ScalarAffineTerm(V[i, j], Xsq[i, j]) for i in 1:n + 2, j in 1:n + 2])
                MOI.add_constraint(optimizer, MOI.ScalarAffineFunction(ctr_aff, 0.0), MOI.EqualTo(d[i, j]^2))
            end
        end
    end
    if verbose
        @show count_all, count
    end
    MOI.add_constraint(optimizer, MOI.SingleVariable(Xsq[1, 1]), MOI.EqualTo(1.0))
    MOI.add_constraint(optimizer, MOI.SingleVariable(Xsq[1, 2]), MOI.EqualTo(0.0))
    MOI.add_constraint(optimizer, MOI.SingleVariable(Xsq[2, 1]), MOI.EqualTo(0.0))
    MOI.add_constraint(optimizer, MOI.SingleVariable(Xsq[2, 2]), MOI.EqualTo(1.0))

    objf_t = [MOI.ScalarAffineTerm(0.0, Xsq[1, 1])]
    if false
        objf_t = [MOI.ScalarAffineTerm(1.0, Xsq[i,i]) for i in 1:n + 2]
    end
    MOI.set(optimizer, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(objf_t, 0.0))

    MOI.set(optimizer, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    MOI.optimize!(optimizer)

    obj = MOI.get(optimizer, MOI.ObjectiveValue())

    Xsq_s = MOI.get.(optimizer, MOI.VariablePrimal(), Xsq)

    verbose && sensorloc_eval(n, m, x_true, Xsq_s)

    return ProxSDP.get_solution(optimizer)
end