import std.stdio;
import std.process: execute;
import std.array: array, join, empty;
import std.path: absolutePath, buildPath, relativePath;
import std.typetuple;
import std.file: exists;
import std.conv: text;
import std.exception: enforce;
import reggae.options;
import reggae.dub_json;


int main(string[] args) {
    try {
        immutable options = getOptions(args);
        enforce(options.projectPath != "", "A project path must be specified");

        if(isDubProject(options.projectPath) && !projectBuildFile(options).exists) {
            createReggaefile(options);
        }

        createBuild(options);
    } catch(Exception ex) {
        stderr.writeln(ex.msg);
        return 1;
    }

    return 0;
}

private void createReggaefile(in Options options) {
    const dubInfo = getDubInfo(options);

    auto file = File("reggaefile.d", "w");
    file.writeln("import reggae;");
    file.writeln("Build bld() {");
    file.writeln("    auto info = ", dubInfo, ";");
    file.writeln("    return Build(info.target);");
    file.writeln("}");

}

private void createBuild(in Options options) {

    immutable buildFileName = getBuildFileName(options);
    enforce(buildFileName.exists, text("Could not find ", buildFileName));

    alias fileNames = TypeTuple!("buildgen_main.d",
                                 "build.d",
                                 "makefile.d", "ninja.d",
                                 "package.d", "range.d", "reflect.d",
                                 "rules.d", "dependencies.d", "types.d",
                                 "dub.d");
    writeSrcFiles!(fileNames)(options);
    string[] reggaeSrcs = [reggaeSrcFileName("config.d")];
    foreach(fileName; fileNames) {
        reggaeSrcs ~= reggaeSrcFileName(fileName);
    }

    immutable reggaeDir = ".reggae";
    immutable binName = buildPath(reggaeDir, "buildgen");
    const compile = ["dmd", "-g", "-debug","-I" ~ options.projectPath,
                     "-of" ~ binName] ~ reggaeSrcs ~ buildFileName;

    immutable retCompBuildgen = execute(compile);
    enforce(retCompBuildgen.status == 0,
            text("Couldn't execute ", compile.join(" "), ":\n", retCompBuildgen.output));

    immutable retRunBuildgen = execute([buildPath(".",  binName), "-b", options.backend, options.projectPath]);
    enforce(retRunBuildgen.status == 0,
            text("Couldn't execute the produced ", binName, " binary:\n", retRunBuildgen.output));

    immutable retCompDcompile = execute(["dmd",
                                         "-of" ~ buildPath(reggaeDir, "dcompile"),
                                         reggaeSrcFileName("dcompile.d"),
                                         reggaeSrcFileName("dependencies.d")]);
    enforce(retCompDcompile.status == 0, text("Couldn't compile dcompile.d:\n", retCompDcompile.output));

}

private bool isDubProject(in string projectPath) @safe {
    return buildPath(projectPath, "dub.json").exists ||
        buildPath(projectPath, "package.json").exists;
}


immutable reggaeSrcDirName = buildPath(".reggae", "src", "reggae");


private void writeSrcFiles(fileNames...)(in Options options) {
    import std.file: mkdirRecurse;
    if(!reggaeSrcDirName.exists) mkdirRecurse(reggaeSrcDirName);

    foreach(fileName; fileNames) {
        auto file = File(reggaeSrcFileName(fileName), "w");
        file.write(import(fileName));
    }

    //necessary due to dmd's lack of -MMD option
    auto file = File(reggaeSrcFileName("dcompile.d"), "w");
    file.write(import("dcompile.d"));

    writeConfig(options);
}


private void writeConfig(in Options options) {
    auto file = File(reggaeSrcFileName("config.d"), "w");
    file.writeln("module reggae.config;");
    file.writeln("import reggae.dub;");
    file.writeln("enum projectPath = `", options.projectPath, "`;");
    file.writeln("enum backend = `", options.backend, "`;");
    file.writeln("enum dflags = `", options.dflags, "`;");
    file.writeln("enum reggaePath = `", options.reggaePath, "`;");

    if(isDubProject(options.projectPath)) {
        auto dubInfo = getDubInfo(options);
        file.writeln("const dubInfo = ", dubInfo, ";");
    }
}


private auto getDubInfo(in Options options) {
    import std.process;
    const string[string] env = null;
    Config config = Config.none;
    size_t maxOutput = size_t.max;
    immutable workDir = options.projectPath;

    immutable dubArgs = ["dub", "describe"];
    immutable ret = execute(dubArgs, env, config, maxOutput, workDir);
    enforce(ret.status == 0, text("Could not get description from dub with ", dubArgs, ":\n",
                                  ret.output));
    return dubInfo(ret.output);
}

private string reggaeSrcFileName(in string fileName) @safe pure nothrow {
    return buildPath(reggaeSrcDirName, fileName);
}

private string projectBuildFile(in Options options) @safe pure nothrow {
    return buildPath(options.projectPath, "reggaefile.d");
}

private string getBuildFileName(in Options options) {
    immutable regular = projectBuildFile(options);
    if(regular.exists) return regular;
    immutable path = isDubProject(options.projectPath) ? "" : options.projectPath;
    return buildPath(path, "reggaefile.d");
}
