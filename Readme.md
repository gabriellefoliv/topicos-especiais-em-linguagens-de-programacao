# Simulação de bilhar 2D — Ponto de contato do taco (Algoritmo 1: força bruta)

Simulação em Julia de uma mesa de bilhar 2D que calcula, em tempo real, o **ponto de contato x(t) = (x1(t), x2(t))** entre a reta do taco e a bola mais próxima.

- **Backend** (`billiards.jl`): matemática, simulação das bolas e algoritmo de interseção.
- **Frontend** (`app.jl`): interface interativa em GLMakie.

---

## 1. Requisitos e execução

- Julia 1.9 ou superior
- Pacote GLMakie (somente para a interface)

```bash
julia -e 'using Pkg; Pkg.add("GLMakie")'   # uma vez
julia app.jl          # abre a interface
julia app.jl bench    # roda só o benchmark do backend (sem interface)
```

Os dois arquivos devem estar na mesma pasta (`app.jl` faz `include("billiards.jl")`).

**Controles da interface**

| Ação            | Efeito                                            |
| --------------- | ------------------------------------------------- |
| Mover o mouse   | Define a direção `d` do taco                      |
| Clique esquerdo | Move a ponta do taco `p` para a posição do clique |
| Slider          | Muda o número de bolas (10 a 100.000)             |

**Legenda visual:** bolas brancas, bola atingida em laranja, reta do taco em amarelo, ponto de contato em vermelho, ponta do taco em azul. A barra inferior mostra N, FPS, tempo do raycast (µs) e as coordenadas do contato.

---

## 2. Formulação matemática

**Reta do taco**, com `p` a ponta do taco e `d` a direção (normalizada, |d| = 1):

```
x1 = p1 + λ d1
x2 = p2 + λ d2
```

São 2 equações e 3 incógnitas (x1, x2, λ).

**Eliminando λ** fica uma única equação em (x1, x2):

```
a x1 + b x2 + c = 0
a = d2,  b = -d1,  c = d1 p2 - d2 p1
```

**Círculo de cada bola** (centro `c = (c1, c2)`, raio `r`):

```
(x1 - c1)^2 + (x2 - c2)^2 = r^2
```

**Interseção.** Como |(a, b)| = 1, a distância com sinal do centro à reta é

```
h = a c1 + b c2 + c
```

- Se `|h| > r`, a reta não toca a bola (descarte sem calcular raiz).
- Se `|h| <= r`, há interseção, e o ponto mais próximo do taco corresponde a

```
λ = d · (c - p) - sqrt(r^2 - h^2)
```

- Só interessa `λ >= 0` (bola à frente do taco).
- Ponto de contato: `x = p + λ d`.

**Algoritmo 1 (força bruta):** aplicar o teste acima a todas as N bolas e ficar com o menor `λ >= 0`. Complexidade **O(N)** por consulta.

---

## 3. Backend — `billiards.jl` (módulo `Billiards`)

Exporta: `Table`, `step!`, `raycast_brute`, `benchmark`.

### `mutable struct Table`

| Campo      | Tipo              | Significado                                 |
| ---------- | ----------------- | ------------------------------------------- |
| `w`, `h`   | `Float64`         | Largura e altura da mesa (padrão 2.0 × 1.0) |
| `r`        | `Float64`         | Raio das bolas (padrão 0.02)                |
| `cx`, `cy` | `Vector{Float64}` | Coordenadas x e y dos centros               |
| `vx`, `vy` | `Vector{Float64}` | Componentes da velocidade                   |

As coordenadas ficam em vetores separados (struct of arrays), o que favorece o acesso contíguo à memória no laço quente.

### `Table(n; w=2.0, h=1.0, r=0.02, speed=0.3)`

Cria `n` bolas com centros aleatórios dentro da mesa (respeitando a margem `r`), direção aleatória e módulo de velocidade aleatório até `speed`. Não verifica sobreposição entre bolas.

### `step!(t::Table, dt::Float64)`

Avança a simulação `dt` segundos:

1. `x ← x + vx·dt`, `y ← y + vy·dt` para cada bola.
2. Se a bola passa da tabela (`x < r`, `x > w - r`, idem em y), ela é recolocada na borda e a componente da velocidade é invertida.

Não há colisão entre bolas, apenas com as tabelas. É o que faz x(t) variar no tempo.

### `raycast_brute(t, p1, p2, d1, d2) -> (idx, x1, x2, λ)`

Implementa o Algoritmo 1.

1. Normaliza `d` (se `|d| = 0`, retorna sem contato).
2. Calcula `a`, `b`, `c` da reta.
3. Para cada bola `i`:
   - `h = a*cx[i] + b*cy[i] + c`
   - Se `h² > r²`, passa para a próxima.
   - Senão, `λ = d1*(cx[i]-p1) + d2*(cy[i]-p2) - sqrt(r² - h²)`.
   - Se `λ >= 0` e `λ < best`, atualiza `best` e `idx`.
4. Retorna `(idx, p1 + best*d1, p2 + best*d2, best)`. Sem contato: `(0, NaN, NaN, Inf)`.

**Detalhes de eficiência**

- Nenhuma alocação dentro do laço.
- `@inbounds` no laço (sem checagem de limites).
- Tipos concretos (`Float64`), permitindo código especializado pelo compilador.
- `sqrt` só é calculada para as bolas que passam no teste `h² <= r²`.

### `benchmark(ns = (10, 100, 1_000, 10_000, 100_000, 1_000_000); reps = 200)`

Para cada N: cria uma mesa, faz um aquecimento (compilação) e mede o tempo médio de `reps` consultas com direções variadas. Imprime N, µs por consulta e consultas por segundo.

---

## 4. Frontend — `app.jl`

### Entrada

Se o primeiro argumento for `bench`, chama `benchmark()` e encerra. Caso contrário, carrega GLMakie e chama `run()`.

### `run(n0 = 50)`

**Estado**

- `tb = Ref(Table(n0))`: mesa atual (em `Ref` para poder ser trocada pelo slider).
- `p = Ref((0.15, h/2))`: ponta do taco.

**Elementos da interface**

- `Axis` com proporção de dados fixa (`DataAspect`) e fundo verde.
- `Slider` com os valores `[10, 50, 100, 500, 1_000, 5_000, 10_000, 50_000, 100_000]`.
- `Label` ligado ao `Observable` `info` (barra de status).

**Observables de desenho:** `pts` (bolas), `hitb` (bola atingida), `ray` (reta do taco), `hitpt` (ponto de contato), `tip` (ponta do taco), `ms` (tamanho do marcador = 2r em unidades de dados).

**Callbacks**

- `on(sl.value)`: recria a mesa com `k` bolas (raio 0.004 se `k > 1000`, senão 0.02) e atualiza os desenhos.
- `on(events(fig).mousebutton)`: clique esquerdo dentro do eixo move `p` e `tip`.

**Laço principal** (`while isopen(fig.scene)`), a cada frame:

1. Calcula `dt` desde o frame anterior e atualiza o FPS (média móvel).
2. `step!(t, min(dt, 0.05))`: limita o passo para evitar saltos grandes.
3. Lê a posição do mouse com `mouseposition(ax)` e calcula `d = mouse - p`.
4. Chama `raycast_brute` e mede o tempo em µs.
5. Atualiza `pts`, `ray`, `hitpt`, `hitb`:
   - Com contato: a reta vai de `p` ao ponto de contato.
   - Sem contato: a reta se estende por 5 unidades na direção `d`.
6. Atualiza o texto de `info` e dorme `1/120` s.

---

## 5. Estrutura dos arquivos

```
.
├── billiards.jl   # backend: Table, step!, raycast_brute, benchmark
├── app.jl         # frontend: interface GLMakie + modo bench
└── README.md
```

---

## 6. Limitações e melhorias possíveis

- Sem colisão bola-bola (apenas bola-tabela).
- Se a ponta do taco estiver dentro de uma bola, essa bola é ignorada (λ negativo).
- O frontend aloca um vetor `Point2f` por frame para desenhar; o backend não aloca.
- O custo continua O(N): para N muito grande, uma grade espacial ou BVH reduziria o número de bolas testadas.
- Paralelismo possível com `Threads.@threads` dividindo as bolas em blocos e combinando o menor λ.

Tempo em segundos que levou pra rodar o frame

Deixar bolas mais lentas e redondas, ponto de interseção claro
