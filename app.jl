# Frontend: interface interativa (GLMakie) para a simulação de bilhar 2D.
#
# Uso:
#   julia -e 'using Pkg; Pkg.add("GLMakie")'      # uma vez
#   julia app.jl                                  # interface
#   julia app.jl bench                            # benchmark do backend
#
# Controles:
#   - mover o mouse    : aponta o taco (direção d)
#   - clique esquerdo  : move a ponta do taco p
#   - slider           : número de bolas (teste de eficiência)

include("billiards.jl")
using .Billiards

if length(ARGS) > 0 && ARGS[1] == "bench"
    benchmark()
    exit()
end

using GLMakie

function run(n0::Int=50)
    tb = Ref(Table(n0))
    p = Ref((0.15, tb[].h / 2))          # ponta do taco

    fig = Figure(size=(1200, 700))
    ax = Axis(fig[1, 1], aspect=DataAspect(),
        limits=(0, tb[].w, 0, tb[].h),
        title="Mesa de bilhar 2D — Algoritmo 1: força bruta")
    hidedecorations!(ax)
    ax.backgroundcolor = RGBf(0.05, 0.4, 0.2)

    sl = Slider(fig[2, 1], range=[10, 50, 100, 500, 1_000, 5_000, 10_000, 50_000, 100_000],
        startvalue=n0)
    info = Observable("")
    Label(fig[3, 1], info, fontsize=16, tellwidth=false)

    # observáveis de desenho
    pts = Observable(Point2f.(tb[].cx, tb[].cy))
    ray = Observable([Point2f(p[]...), Point2f(p[]...)])
    hitpt = Observable(Point2f[])
    hitb = Observable(Point2f[])
    tip = Observable([Point2f(p[]...)])

    msize() = max(2 * tb[].r, 0.0)
    ms = Observable(msize())
    scatter!(ax, pts, markersize=ms, markerspace=:data, color=:white,
        strokecolor=:black, strokewidth=0.5)
    scatter!(ax, hitb, markersize=ms, markerspace=:data, color=:orange)
    lines!(ax, ray, color=:yellow, linewidth=2)
    scatter!(ax, hitpt, markersize=10, color=:red)
    scatter!(ax, tip, markersize=12, color=:cyan)

    # trocar número de bolas
    on(sl.value) do k
        tb[] = Table(k; r=k > 1_000 ? 0.004 : 0.02)
        ms[] = msize()
        pts[] = Point2f.(tb[].cx, tb[].cy)
    end

    # clique esquerdo move o taco
    on(events(fig).mousebutton) do ev
        if ev.button == Mouse.left && ev.action == Mouse.press && is_mouseinside(ax)
            m = mouseposition(ax)
            p[] = (m[1], m[2])
            tip[] = [Point2f(m...)]
        end
    end

    display(fig)

    last = time_ns()
    fps = 60.0
    while isopen(fig.scene)
        now = time_ns()
        dt = (now - last) / 1e9
        last = now
        fps = 0.95fps + 0.05 / max(dt, 1e-6)

        t = tb[]
        step!(t, min(dt, 0.05))

        m = mouseposition(ax)
        d1, d2 = m[1] - p[][1], m[2] - p[][2]

        t0 = time_ns()
        idx, x1, x2, λ = raycast_brute(t, p[][1], p[][2], d1, d2)
        µs = (time_ns() - t0) / 1e3

        pts[] = Point2f.(t.cx, t.cy)
        nd = hypot(d1, d2)
        if idx > 0
            ray[] = [Point2f(p[]...), Point2f(x1, x2)]
            hitpt[] = [Point2f(x1, x2)]
            hitb[] = [Point2f(t.cx[idx], t.cy[idx])]
            msg = "contato x = ($(round(x1, digits=3)), $(round(x2, digits=3))) | bola #$idx"
        else
            far = nd > 0 ? 5 / nd : 0.0
            ray[] = [Point2f(p[]...), Point2f(p[][1] + d1 * far, p[][2] + d2 * far)]
            hitpt[] = Point2f[]
            hitb[] = Point2f[]
            msg = "sem contato"
        end
        info[] = "N = $(length(t.cx)) | FPS ≈ $(round(Int, fps)) | raycast = $(round(µs, digits=1)) µs | " * msg
        sleep(1 / 120)
    end
end

run()