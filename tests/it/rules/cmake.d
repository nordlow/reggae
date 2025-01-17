module tests.it.rules.cmake;

import tests.it.runtime;
import tests.utils;
import reggae.reggae;

@("cmake")
unittest {
    import std.format : format;
    import std.path : buildNormalizedPath;

    with(immutable ReggaeSandbox()) {
        writeFile("calculator.cpp", `
            #include "calculator.h"
            int addNumbersInc(int a, int b) { return a + b + 1; }`
        );

        writeFile("calculator.h", `int addNumbersInc(int a, int b);`);

        writeFile("main.cpp", `
            #include <iostream>
            #include <cstdlib>
            #include "calculator.h"

            int main(int argc, char *argv[])
            {
                int num1 = std::atoi(argv[1]);
                int num2 = std::atoi(argv[2]);
                std::cout << addNumbersInc(num1, num2) << std::endl;
                return 0;
            }
        `);

        writeFile("CMakeLists.txt", `
            cmake_minimum_required(VERSION 3.10)
            project(AddTwoNumbersInc)
            add_executable(add_two_numbers_inc main.cpp calculator.cpp)
            target_include_directories(add_two_numbers_inc PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
        `);

        writeFile("reggaefile.d",
                q{
                    import reggae;
                    Build reggaeBuild() {
                        auto cmakeTargets = cmakeBuild!(ProjectPath(`%s`), Configuration("Release"), [],
                                                        CMakeFlags("-G Ninja -D CMAKE_BUILD_TYPE=Release"));
                        return Build(cmakeTargets);
                    }
                }.format(currentTestPath)
        );

        runReggae("-b", "ninja");
        ninja.shouldExecuteOk;
        [buildNormalizedPath(currentTestPath, "add_two_numbers_inc"), "3", "4"].shouldExecuteOk.shouldEqual(["8"]);
    }
}
