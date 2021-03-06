function mimo_data(seed, m, n)
    Random.seed!(seed)
    # Channel
    H = randn((m, n))
    # Gaussian noise
    v = randn((m, 1))
    # True signal
    s = rand([-1, 1], n)
    # Received signal
    sigma = .0001
    y = H * s + sigma * v
    L = [hcat(H' * H, -H' * y); hcat(-y' * H, y' * y)]
    return s, H, y, L
end

function mimo_eval(s, H, y, L, XX)
    x_hat = sign.(XX[1:end-1, end])
    rank = length([eig for eig in eigen(XX).values if eig > 1e-7])
    @show decode_error = sum(abs.(x_hat - s))
    @show rank
    @show norm(y - H * x_hat)
    @show norm(y - H * s)
    @show tr(L * XX)
    return nothing
end