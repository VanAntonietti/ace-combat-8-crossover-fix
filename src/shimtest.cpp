// Offline check: feed the original shader to Apple's converter directly (expected: error 19)
// and through the shim (expected: compiles).
// usage: shimtest <original.dxbc> <path/to/libmetalirconverter_real.dylib>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <vector>
struct IRObject; struct IRCompiler; struct IRError;
extern "C" {
IRCompiler* IRCompilerCreate(void);
void IRCompilerDestroy(IRCompiler*);
unsigned IRErrorGetCode(const IRError*);
void IRErrorDestroy(IRError*);
void IRObjectDestroy(IRObject*);
}
IRObject* IRObjectCreateFromDXIL(const char*, unsigned long);
IRObject* IRCompilerAllocCompileAndLink(IRCompiler*, const std::vector<std::string>&, const IRObject*, IRError**);

static std::vector<char> slurp(const char* p) {
    FILE* f = fopen(p, "rb");
    if (!f) { perror(p); exit(2); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    std::vector<char> v(n);
    if (fread(v.data(), 1, n, f) != (size_t)n) exit(2);
    fclose(f);
    return v;
}

static unsigned compile(IRObject* in) {  // 0 = ok, otherwise the converter's error code
    IRCompiler* c = IRCompilerCreate();
    IRError* e = nullptr;
    std::vector<std::string> entry = {"TraceTilesClassifyCS"};
    IRObject* out = IRCompilerAllocCompileAndLink(c, entry, in, &e);
    unsigned code = 0;
    if (out) IRObjectDestroy(out);
    else { code = e ? IRErrorGetCode(e) : 9999; if (e) IRErrorDestroy(e); }
    IRCompilerDestroy(c);
    return code;
}

int main(int argc, char** argv) {
    if (argc < 3) { fprintf(stderr, "usage: shimtest <original.dxbc> <libmetalirconverter_real.dylib>\n"); return 2; }
    auto orig = slurp(argv[1]);
    void* h = dlopen(argv[2], RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 2; }
    auto real = (IRObject* (*)(const char*, unsigned long))dlsym(h, "_Z22IRObjectCreateFromDXILPKcm");
    unsigned direct = compile(real(orig.data(), orig.size()));
    unsigned shimmed = compile(IRObjectCreateFromDXIL(orig.data(), orig.size()));
    printf("original shader, Apple converter directly: %s (code %u)\n", direct ? "FAILED" : "compiled", direct);
    printf("original shader, through the shim:         %s (code %u)\n", shimmed ? "FAILED" : "compiled", shimmed);
    if (direct == 0) printf("note: the stock converter now accepts this shader; you may not need the shim.\n");
    return shimmed ? 1 : 0;
}
