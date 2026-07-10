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

The target is Linux. Run it in a container:

```sh
docker build -t asm .
docker run --rm -it -v "$PWD":/asm asm
make        # inside the container
```

Or zero commands: open the repo in VS Code with the Dev Containers extension and hit "Reopen in Container".

Note: buffers live in `.data`, not `.bss` — Rosetta's x86 translation chokes on pure-bss load segments (`rosetta error: bss_size overflow`).

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
- [ ] an HTTP server in raw syscalls (`socket`, `bind`, `listen`, `accept`)
- [ ] threads with `clone()` + my own mutex (hello `futex`)
- [ ] SHA-256 in pure asm
- [ ] Mandelbrot, vectorized with AVX2
- [ ] Tetris in the terminal (Pong is cute)

### Boss fights

- [ ] **[AMBITIOUS]** a Forth interpreter
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