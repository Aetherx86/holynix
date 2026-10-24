class CPerson {
    U8 name[32];
    I64 age;
};

U0 Yield() {
    "Yielding CPU time...\n";
}

I32 main() {
    "Divine TempleOS Test\n";
    CPerson p;
    StrCpy(p.name, "Terry Davis");
    p.age = 48;
    "User: %s, Age: %d\n", p.name, p.age;
    Yield;
    return 0;
}
