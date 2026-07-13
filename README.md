# learn assembly with em

> Drowning in C? Dive deeper — after assembly, C feels like floating

The piscine teaches you to swim.

This repo is the bottom of the pool.

## Ground rules

- x86_64, Linux, NASM
- no libc, no external calls — `syscall` or nothing
- if it segfaults, it builds character

## Build

```sh
make        # binaries land in bin/
```

### on macOS

The target is Linux, so run it in a container. Any OCI runtime works — Docker,
Podman, Colima, OrbStack — they all read the same `Dockerfile`:

```sh
docker build -t asm .
docker run --rm -it -v "$PWD":/asm asm
make        # inside the container
```

What I actually use: [OrbStack](https://orbstack.dev) + VS Code's Dev Containers extension. 
Open the repo, "Reopen in Container", and the terminal drops you straight into Linux with `make` ready — no container commands at all. 
On Apple Silicon, Rosetta handles the x86 translation.

Note: buffers live in `.data`, not `.bss` — Rosetta's x86 translation chokes on pure-bss load segments (`rosetta error: bss_size overflow`).

## Usage

```sh
# warm-up
./bin/max3 4 17 9                       # -> 17
./bin/fib 10                            # -> 55
./bin/factorial 5                       # -> 120
./bin/quicksort 3 1 4 1 5 9 2 6         # -> sorted

# coreutils (match their GNU counterparts)
./bin/cat README.md
./bin/wc README.md
./bin/ls .
./bin/grep syscall warmup/hello.asm
cat README.md | ./bin/grep piscine      # they pipe, too

# the real stuff
./bin/printf                            # demo: format specifiers, matches glibc
./bin/malloc                            # demo: alloc/free/coalesce assertions
./bin/threads                           # race without a lock, correct with one
printf 'abc' | ./bin/sha256             # -> matches sha256sum
./bin/mandelbrot                        # AVX2 fractal, 8 pixels per iteration
./bin/shell                             # a shell: em$ prompt, pipes, redirections
./bin/tetris                            # a/d move, w rotate, s drop, q quit

# boss fights
./bin/forth                             # a Forth REPL: `2 3 + .` -> 5, define words with `: ;`
```

## Roadmap

### Warm-up

- [x] hello world (syscalls, registers, variables — the usual)
- [x] max of three, fibonacci, factorial
- [x] quicksort (recursion, stack frames, array manipulation)
- [x] `cat`, `wc`, `ls`, `grep` — yes, all four. still warm-up

### The real stuff

- [x] `printf` from scratch (varargs by hand, format parsing, the works)
- [x] `malloc` from scratch (`brk`/`mmap`, free lists, alignment)
- [x] a shell — `fork`, `execve`, pipes, redirections
- [x] an HTTP server in raw syscalls (`socket`, `bind`, `listen`, `accept`)
- [x] threads with `clone()` + my own mutex (hello `futex`)
- [x] SHA-256 in pure asm
- [x] Mandelbrot, vectorized with AVX2
- [x] Tetris in the terminal (Pong is cute)

### Boss fights

- [x] **[AMBITIOUS]** a Forth interpreter
- [ ] **[VERY AMBITIOUS]** a self-hosting assembler — written in assembly, assembling itself
- [ ] **[UNREASONABLE]** a bootloader + bare-metal hello world. no OS, just me and the CPU
- [ ] **[SEEK HELP]** a mini-kernel with its own syscalls

## TODO

~~Take notes on tips and tricks~~ — the Intel manual is only ~5,000 pages, perfectly reasonable bedtime reading.

## Useful resources

- Intel® 64 and IA-32 Architectures Software Developer's Manual (all volumes, obviously)
- `man 2 <literally anything>`
- Agner Fog's optimization manuals (for when it works but not fast enough)
- the osdev wiki (for the boss fights)
- a rubber duck with low expectations

## FAQ

**Why?**

Why not.

**Isn't reimplementing `wc` supposed to be, like, VERY AMBITIOUS?**