.intel_syntax noprefix

# Constants and syscall definitions for the Rubix compiler
.equ SYS_READ, 0
.equ SYS_WRITE, 1
.equ SYS_OPEN, 2
.equ SYS_CLOSE, 3
.equ SYS_MMAP, 9
.equ SYS_EXIT, 60

# File flags
.equ O_RDONLY, 0
.equ O_WRONLY, 1
.equ O_CREAT, 64
.equ O_TRUNC, 512

# File descriptors
.equ STDIN, 0
.equ STDOUT, 1
.equ STDERR, 2

# Token Types
.equ TOK_EOF, 0
.equ TOK_INT, 1
.equ TOK_IDENT, 2
.equ TOK_STR, 3

# Keywords & Literals
.equ TOK_FN, 10
.equ TOK_LET, 11
.equ TOK_IF, 12
.equ TOK_ELSE, 13
.equ TOK_WHILE, 14
.equ TOK_RETURN, 15
.equ TOK_IMPORT, 16
.equ TOK_TRUE, 17
.equ TOK_FALSE, 18
.equ TOK_CHAR_LIT, 19
.equ TOK_CHAR, 20
.equ TOK_BOOL, 21
.equ TOK_CHAR_KW, 20
.equ TOK_BOOL_KW, 21

# Operators & Punctuation
.equ TOK_PLUS, 30
.equ TOK_MINUS, 31
.equ TOK_STAR, 32
.equ TOK_SLASH, 33
.equ TOK_PERCENT, 34
.equ TOK_ASSIGN, 35
.equ TOK_EQ, 36
.equ TOK_NEQ, 37
.equ TOK_LT, 38
.equ TOK_LTE, 39
.equ TOK_GT, 40
.equ TOK_GTE, 41
.equ TOK_LPAREN, 42
.equ TOK_RPAREN, 43
.equ TOK_LBRACE, 44
.equ TOK_RBRACE, 45
.equ TOK_COMMA, 46
.equ TOK_SEMICOLON, 47
.equ TOK_LBRACKET, 48       # [
.equ TOK_RBRACKET, 49       # ]
.equ TOK_AND, 50            # &&
.equ TOK_OR, 51             # ||
.equ TOK_NOT, 52            # !
.equ TOK_COLON, 53          # :
.equ TOK_BREAK, 54          # break
.equ TOK_CONTINUE, 55       # continue
.equ TOK_FOR, 56            # for

# Expanded Buffer and Table Capacities (Zero-limit scalability)
.equ SRC_BUF_SIZE, 8388608      # 8 MB source code buffer
.equ MAX_TOKENS, 262144         # 256K tokens (~50,000 lines of code)
.equ TOKEN_SIZE, 32             # 32 bytes per token: type(8), val/ptr(8), len(8), line(8)
.equ OUT_BUF_SIZE, 16777216     # 16 MB output assembly buffer
.equ FN_BODY_BUF_SIZE, 8388608  # 8 MB per function body buffer
.equ RODATA_BUF_SIZE, 1048576   # 1 MB rodata string literal buffer
.equ MAX_SYMBOLS, 1024          # 1,024 symbols per function
.equ SYMBOL_SIZE, 96             # name(64 bytes) + name_len(8) + stack_offset(8) + pad(16)
.equ MAX_USER_FNS, 1024         # 1,024 user-defined functions
.equ MAX_PARAMS, 64             # Up to 64 function arguments
.equ MAX_IMPORTS, 256           # Up to 256 imported modules
.equ MAX_LOOP_DEPTH, 64         # Max nested loops for break/continue tracking
