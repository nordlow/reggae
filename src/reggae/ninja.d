module reggae.ninja;


import reggae.build;
import reggae.range;
import std.array;
import std.range;
import std.algorithm;
import std.exception: enforce;
import std.conv: text;
import std.string: strip;

struct NinjaEntry {
    string mainLine;
    string[] paramLines;
    string toString() @safe pure nothrow const {
        return (mainLine ~ paramLines.map!(a => "  " ~ a).array).join("\n");
    }
}


struct Ninja {
    NinjaEntry[] buildEntries;
    NinjaEntry[] ruleEntries;

    this(Build build, in string projectPath = "") {
        _build = build;
        _projectPath = projectPath;

        foreach(target; DepthFirst(_build.targets[0])) {
            import std.regex;
            auto reg = regex(`^[^ ]+ +(.*?)(\$in|\$out)(.*?)(\$in|\$out)(.*?)$`);
            auto rawCmdLine = target.inOutCommand(_projectPath);
            auto mat = rawCmdLine.match(reg);
            enforce(!mat.captures.empty, text("Command: ", rawCmdLine, ", Captures: ", mat.captures));
            immutable before = mat.captures[1].strip;
            immutable first = mat.captures[2];
            immutable between = mat.captures[3].strip;
            immutable last  = mat.captures[4];
            immutable after = mat.captures[5].strip;

            immutable ruleCmdLine = getRuleCommandLine(target, before, first, between, last, after);
            bool haveToAdd;
            immutable ruleName = getRuleName(targetCommand(target), ruleCmdLine, haveToAdd);
            immutable buildLine = "build " ~ target.outputs[0] ~ ": " ~ ruleName ~
                " " ~ target.dependencyFiles(_projectPath);
            string[] buildParamLines;
            if(!before.empty)  buildParamLines ~= "before = "  ~ before;
            if(!between.empty) buildParamLines ~= "between = " ~ between;
            if(!after.empty)   buildParamLines ~= "after = "   ~ after;

            buildEntries ~= NinjaEntry(buildLine, buildParamLines);

            if(haveToAdd) {
                ruleEntries ~= NinjaEntry("rule " ~ ruleName,
                                          [ruleCmdLine]);
            }
        }
    }

    string getRuleCommandLine(in Target target, in string before, in string first, in string between,
                              in string last, in string after) {
        immutable rawCmdLine = target.inOutCommand(_projectPath);
        auto cmdLine = "command = " ~ targetRawCommand(target);
        if(!before.empty) cmdLine ~= " $before";
        cmdLine ~= rawCmdLine.canFind(" " ~ first) ? " " ~ first : first;
        if(!between.empty) cmdLine ~= " $between";
        cmdLine ~= rawCmdLine.canFind(" " ~ last) ? " " ~ last : last;
        if(!after.empty) cmdLine ~= " $after";
        return cmdLine;
    }

//Ninja operates on rules, not commands. Since this is supposed to work with
//generic build systems, the same command can appear with different parameter
//ordering. The first time we create a rule with the same name as the command.
//The subsequent times, if any, we append a number to the command to create
//a new rule
string getRuleName(in string cmd, in string ruleCmdLine, out bool haveToAdd) {
    immutable ruleMainLine = "rule " ~ cmd;
    //don't have a rule for this cmd yet, return just the cmd
    if(!ruleEntries.canFind!(a => a.mainLine == ruleMainLine)) {
        haveToAdd = true;
        return cmd;
    }

    //so we have a rule for this already. Need to check if the command line
    //is the same

    //same cmd: either matches exactly or is cmd_{number}
    auto isSameCmd = (in NinjaEntry entry) {
        bool sameMainLine = entry.mainLine.startsWith(ruleMainLine) &&
        (entry.mainLine == ruleMainLine || entry.mainLine[ruleMainLine.length] == '_');
        bool sameCmdLine = entry.paramLines == [ruleCmdLine];
        return sameMainLine && sameCmdLine;
    };

    auto rulesWithSameCmd = ruleEntries.filter!isSameCmd;
    assert(rulesWithSameCmd.empty || rulesWithSameCmd.array.length == 1);

    //found a sule with the same cmd and paramLines
    if(!rulesWithSameCmd.empty) return rulesWithSameCmd.front.mainLine.replace("rule ", "");

    //if we got here then it's the first time we see "cmd" with a new
    //ruleCmdLine, so we add it
    haveToAdd = true;
    import std.conv: to;
    static int counter = 1;
    return cmd ~ "_" ~ (++counter).to!string;
}

private:
    Build _build;
    string _projectPath;
}

//@trusted because of splitter
private string targetCommand(in Target target) @trusted pure nothrow {
    return target.command.splitter(" ").front.sanitizeCmd;
}

//@trusted because of splitter
private string targetRawCommand(in Target target) @trusted pure nothrow {
    return target.command.splitter(" ").front;
}

//@trusted because of replace
private string sanitizeCmd(in string cmd) @trusted pure nothrow {
    import std.path;
    //only handles c++ compilers so far...
    return cmd.baseName.replace("+", "p");
}