"""
Backend: mesa de bilhar 2D + Algoritmo 1 (força bruta) para o ponto de contato do taco.

Matemática
----------
Reta do taco:  x(t) = p(t) + λ d(t),  |d| = 1
  x1 = p1 + λ d1
  x2 = p2 + λ d2     (2 equações, 3 incógnitas: x1, x2, λ)

Eliminando λ  ->  a x1 + b x2 + c = 0, com
  a = d2,  b = -d1,  c = d1 p2 - d2 p1

Bola i: (x1 - c1)^2 + (x2 - c2)^2 = r^2

Como |(a,b)| = 1, a distância do centro à reta é  h = a c1 + b c2 + c.
  |h| > r  -> a reta não toca a bola (rejeição barata, sem sqrt)
  |h| <= r -> λ = d·(c - p) - sqrt(r^2 - h^2)   (interseção mais próxima do taco)
Só vale se λ >= 0 (bola à frente do taco).

Ponto de contato: x = p + λ d. Retorna-se o de menor λ entre todas as bolas: O(N).
Sem alocações no laço quente -> centenas de milhares de bolas em tempo real.
"""
module Billiards

export Table, step!, raycast_brute, benchmark

mutable struct Table
    w::Float64
    h::Float64
    r::Float64
    cx::Vector{Float64}
    cy::Vector{Float64}
    vx::Vector{Float64}
    vy::Vector{Float64}
end

"Mesa com n bolas em posições e velocidades aleatórias."
function Table(n::Int; w=2.0, h=1.0, r=0.02, speed=0.3)
    cx = r .+ rand(n) .* (w - 2r)
    cy = r .+ rand(n) .* (h - 2r)
    θ = 2π .* rand(n)
    v = speed .* rand(n)
    return Table(w, h, r, cx, cy, v .* cos.(θ), v .* sin.(θ))
end

"Avança a simulação dt segundos (movimento retilíneo + rebote nas tabelas)."
function step!(t::Table, dt::Float64)
    r, w, h = t.r, t.w, t.h
    cx, cy, vx, vy = t.cx, t.cy, t.vx, t.vy
    @inbounds for i in eachindex(cx)
        x = cx[i] + vx[i] * dt
        y = cy[i] + vy[i] * dt
        if x < r
            x = r
            vx[i] = -vx[i]
        elseif x > w - r
            x = w - r
            vx[i] = -vx[i]
        end
        if y < r
            y = r
            vy[i] = -vy[i]
        elseif y > h - r
            y = h - r
            vy[i] = -vy[i]
        end
        cx[i] = x
        cy[i] = y
    end
    return t
end

"""
    raycast_brute(t, p1, p2, d1, d2) -> (idx, x1, x2, λ)

Algoritmo 1 (força bruta). p = origem do taco, d = direção (não precisa ser unitária).
Retorna índice da bola atingida e o ponto de contato x = (x1, x2) mais próximo do taco.
Se nada for atingido: idx = 0 e x1 = x2 = NaN.
"""
function raycast_brute(t::Table, p1::Float64, p2::Float64, d1::Float64, d2::Float64)
    n = hypot(d1, d2)
    n == 0 && return (0, NaN, NaN, Inf)
    d1 /= n
    d2 /= n
    # reta eliminando λ: a x1 + b x2 + c = 0
    a = d2
    b = -d1
    c = d1 * p2 - d2 * p1
    r = t.r
    r2 = r * r
    cx, cy = t.cx, t.cy
    best = Inf
    idx = 0
    @inbounds for i in eachindex(cx)
        h = a * cx[i] + b * cy[i] + c          # distância com sinal centro-reta
        h2 = h * h
        h2 > r2 && continue                    # reta não intercepta o círculo
        λ = d1 * (cx[i] - p1) + d2 * (cy[i] - p2) - sqrt(r2 - h2)
        if λ >= 0 && λ < best
            best = λ
            idx = i
        end
    end
    idx == 0 && return (0, NaN, NaN, Inf)
    return (idx, p1 + best * d1, p2 + best * d2, best)
end

"Mede o tempo médio (µs) do raycast para vários N."
function benchmark(ns=(10, 100, 1_000, 10_000, 100_000, 1_000_000); reps=200)
    println("   N bolas | µs por consulta | consultas/s")
    for n in ns
        t = Table(n)
        raycast_brute(t, 0.1, 0.5, 1.0, 0.1)   # aquecimento (compila)
        t0 = time_ns()
        for k in 1:reps
            ang = 2π * k / reps
            raycast_brute(t, 0.1, 0.5, cos(ang), sin(ang))
        end
        us = (time_ns() - t0) / 1e3 / reps
        println(lpad(n, 10), " | ", lpad(round(us, digits=2), 15), " | ", lpad(round(Int, 1e6 / us), 11))
    end
end

end # module