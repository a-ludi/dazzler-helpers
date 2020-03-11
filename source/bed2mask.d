/+ dub.sdl:
    name              "bed2mask"
    description       "Convert a BED file to a Dazzler mask."
    authors           "Arne Ludwig <arne.ludwig@posteo.de>"
    copyright         "Copyright © 2020, Arne Ludwig <arne.ludwig@posteo.de>"
    license           "MIT"
+/

import std.algorithm;
import std.array;
import std.ascii;
import std.conv;
import std.exception;
import std.file;
import std.format;
import std.json;
import std.path;
import std.process;
import std.range;
import std.stdio;
import std.string;
import std.typecons;


immutable(string) program;


struct CLIOptions
{
    enum usageString = "USAGE:  %s [-hiCvx] [--version] <dam> <mask>";
    enum description = "Convert a BED file to a Dazzler mask.";
    enum version_ = "v0.2.0";
    enum versionString = [
        "%s v0.2.0",
        "",
        "Copyright © 2020, Arne Ludwig <arne.ludwig@posteo.de>",
        "",
        "Subject to the terms of the MIT license, as written in the included LICENSE file",
    ].join('\n');

    string bedFile = "/dev/stdin";
    string damFile;
    string maskName;
    bool contigCoords;
    uint cutoff;
    bool verbose;
    bool printVersion;


    JSONValue toJson() const
    {
        return JSONValue([
            "bedFile": JSONValue(bedFile),
            "damFile": JSONValue(damFile),
            "maskName": JSONValue(maskName),
            "contigCoords": JSONValue(contigCoords),
            "cutoff": JSONValue(cutoff),
        ]);
    }
};


void setProgram(string[] args) nothrow @trusted
in (program is null, "must be called only once")
out (; program !is null, "program was not modified")
{
    if (program is null)
        *(cast(string*) &program) = baseName(args[0]);
}


void enforceUsage(bool testPassed, lazy string message)
{
    enforce(
        testPassed,
        format!"%s\n%s"(message, format!(CLIOptions.usageString)(program)),
    );
}


T reportException(E : Throwable = Exception, T)(lazy T expr, lazy string message)
{
    try
    {
        return expr;
    }
    catch(E e)
    {
        throw new Exception(format!"%s: %s"(message, e.toString()));
    }
}


CLIOptions parseOptions(string[] args)
{
    import core.stdc.stdlib : exit;
    import std.getopt;

    CLIOptions options;

    auto helpInfo = getopt(
        args,
        "input|i",
            "Specify a BED file instead of standard input",
            &options.bedFile,
        "contig-coords|C",
            "BED entries relate to contig coordinates as used in the Dazzler DB files",
            &options.contigCoords,
        "cutoff|x",
            "Ignore mask intervals smaller than the cutoff (default: 0)",
            &options.cutoff,
        "verbose|v",
            "Get more output",
            &options.verbose,
        "version",
            "Print version and license of this program",
            &options.printVersion,
    );

    if (helpInfo.helpWanted)
    {
        stderr.writefln!(CLIOptions.usageString)(program);
        stderr.writeln();
        stderr.lockingTextWriter.defaultGetoptFormatter(
            CLIOptions.description ~ "\n\nOptional Arguments:",
            helpInfo.options,
        );

        exit(0);
    }

    if (options.printVersion)
    {
        stderr.writefln!(CLIOptions.versionString)(program);

        exit(0);
    }

    enforceUsage(args.length > 1, "missing input database <dam>");
    options.damFile = args[1];
    enforceUsage(args.length > 2, "missing output mask name <mask>");
    options.maskName = args[2];
    enforceUsage(args.length <= 3, "too many arguments");

    reportException(
        File(options.damFile, "rb"),
        format!"could not read `%s`"(options.damFile),
    );
    reportException(
        File(options.bedFile, "rb"),
        format!"could not read `%s`"(options.bedFile),
    );
    enforce(options.cutoff < 2^^30, "--cutoff must be less than 1 Gbp");
    enforce(
        !options.maskName.any!(c => c == '.'),
        "<mask> must not contain dots (`.`)",
    );

    return options;
}


alias MaskHeaderEntry = int;
alias MaskDataPointer = long;
alias MaskDataEntry = int;
alias MaskInterval = Tuple!(
    MaskHeaderEntry, "contigId",
    MaskDataEntry, "begin",
    MaskDataEntry, "end",
);


struct Contig
{
    string scaffold;
    MaskDataEntry begin;
    MaskDataEntry end;


    @property MaskDataEntry length() const pure nothrow @safe
    {
        return end - begin;
    }
}


void writeMask(
    const string dbFile,
    const size_t numContigs,
    const string maskName,
    ref MaskInterval[] maskIntervals,
)
{
    auto maskBaseName = buildPath(
        dbFile.dirName,
        format!".%s.%s"(dbFile.baseName.stripExtension, maskName),
    );
    auto maskHeader = File(maskBaseName ~ ".anno", "wb");
    auto maskData = File(maskBaseName ~ ".data", "wb");

    maskIntervals.sort();

    MaskHeaderEntry size = 0; // Mark the DAZZ_TRACK as a mask (see DAZZ_DB/DB.c:1183)
    MaskHeaderEntry currentContig = 1;
    MaskDataPointer dataPointer = 0;

    maskHeader.rawWrite([numContigs.to!MaskHeaderEntry, size]);
    maskHeader.rawWrite([dataPointer]);
    foreach (maskInterval; maskIntervals)
    {
        assert(maskInterval.contigId >= currentContig);

        while (maskInterval.contigId > currentContig)
        {
            maskHeader.rawWrite([dataPointer]);
            ++currentContig;
        }

        if (maskInterval.contigId == currentContig)
        {
            maskData.rawWrite([maskInterval.begin, maskInterval.end]);
            dataPointer += typeof(maskInterval.begin).sizeof + typeof(maskInterval.end).sizeof;
        }
    }

    foreach (emptyContig; currentContig .. numContigs + 1)
        maskHeader.rawWrite([dataPointer]);
}


struct Bed2MaskConverter
{
    const(CLIOptions) options;
    Contig[] contigs;
    size_t[string] scaffoldIndex;
    MaskInterval[] maskIntervals;


    void run()
    {
        logDebug(options.toJson);
        readDbStructure();
        logDebug(JSONValue(["numContigs": contigs.length]));
        convertBedFile();
        logDebug(JSONValue(["numMaskIntervals": maskIntervals.length]));
        writeMask(
            options.damFile,
            contigs.length,
            options.maskName,
            maskIntervals,
        );
    }


    void readDbStructure()
    {
        auto dbdump = pipeProcess(["DBdump", "-rh", options.damFile]);

        scope (success)
        {
            auto errorMessage = dbdump.stderr.isOpen
                ? cast(string) dbdump.stderr.rawRead(new char[2^^10])
                : null;

            dbdump.stdin.close();
            dbdump.stdout.close();
            dbdump.stderr.close();
            auto exitCode = wait(dbdump.pid);

            if (exitCode != 0)
                throw new Exception(errorMessage);
        }
        scope (failure)
        {
            dbdump.stdin.close();
            dbdump.stdout.close();
            dbdump.stderr.close();
            wait(dbdump.pid);
        }

        char[][] fields;
        void splitIntoFields(char[] line) { fields = line.split!isWhite; }
        alias field = (size_t idx) => idx < fields.length ? fields[idx] : null;
        size_t currentContigIdx;
        string lastScaffold;

        foreach (line; dbdump.stdout.byLine.filter!"a.length > 0")
        {
            switch (line[0])
            {
                case '+':
                    splitIntoFields(line);
                    if (field(1) == "R")
                        contigs = new Contig[field(2).to!size_t];

                    break;
                case 'R':
                    splitIntoFields(line);
                    currentContigIdx = field(1).to!size_t - 1;
                    break;
                case 'H':
                    splitIntoFields(line);
                    string scaffold = field(2)[1 .. $].dup;
                    if (lastScaffold != scaffold)
                        scaffoldIndex[scaffold] = currentContigIdx;
                    contigs[currentContigIdx].scaffold = scaffold;
                    lastScaffold = scaffold;
                    break;
                case 'L':
                    splitIntoFields(line);
                    contigs[currentContigIdx].begin = field(2).to!MaskDataEntry;
                    contigs[currentContigIdx].end = field(3).to!MaskDataEntry;
                    break;
                default: break;
            }
        }
    }


    void convertBedFile()
    {
        auto bedEntries = File(options.bedFile, "r")
            .byLine
            .map!(line => line.split!isWhite)
            .enumerate
            .filter!(enumLine => enumLine.value.length > 0);
        auto intervalsAcc = appender!(MaskInterval[]);
        intervalsAcc.reserve(2*contigs.length);

        foreach (line, bedEntry; bedEntries)
        {
            try
            {
                enforce(
                    bedEntry.length >= 3,
                    "missing fields: expected at least 3 fields",
                );

                if (options.contigCoords)
                    convertDazzBedEntry(intervalsAcc, cast(string[]) bedEntry, options.bedFile, line + 1);
                else
                    convertBedEntry(intervalsAcc, cast(string[]) bedEntry, options.bedFile, line + 1);
            }
            catch (Exception e)
            {
                logWarning(JSONValue([
                    "message": JSONValue("mappingFailed"),
                    "file": JSONValue(options.bedFile),
                    "line": JSONValue(line + 1),
                    "bedEntry": JSONValue(bedEntry),
                    "error": JSONValue(e.toString().split('\n')),
                ]));
            }
        }

        maskIntervals = intervalsAcc.data;
    }


    void convertBedEntry(ref Appender!(MaskInterval[]) intervalsAcc, scope string[] bedEntry, string file, size_t line)
    {
        auto scaffold = bedEntry[0];
        auto scaffoldIdx = scaffoldIndex.get(scaffold, size_t.max);
        auto bedBegin = bedEntry[1].to!MaskDataEntry;
        auto bedEnd = bedEntry[2].to!MaskDataEntry;

        if (scaffoldIdx >= contigs.length)
            return logWarning(JSONValue([
                "message": JSONValue("unmappedInterval"),
                "reason": JSONValue("unkownScaffold"),
                "file": JSONValue(file),
                "line": JSONValue(line),
                "targetScaffold": JSONValue(scaffold),
            ]));

        logDebug(JSONValue([
            "message": JSONValue("beginSearch"),
            "file": JSONValue(file),
            "line": JSONValue(line),
            "scaffold": JSONValue(scaffold),
            "scaffoldIndex": JSONValue(scaffoldIdx),
            "indexedScaffold": JSONValue(contigs[scaffoldIdx].scaffold),
        ]));

        size_t numMappedIntervals;
        size_t numSplitParts;
        foreach (i, contig; contigs[scaffoldIdx .. $])
        {
            auto contigId = to!MaskHeaderEntry(scaffoldIdx + i + 1);

            if (contig.scaffold != scaffold)
            {
                logDebug(JSONValue([
                    "message": JSONValue("breakSearch"),
                    "file": JSONValue(file),
                    "line": JSONValue(line),
                    "reason": JSONValue("endOfScaffold"),
                    "targetScaffold": JSONValue(scaffold),
                    "currentScaffold": JSONValue(contig.scaffold),
                ]));
                break;
            }
            else if (bedEnd < contig.begin)
            {
                logDebug(JSONValue([
                    "message": JSONValue("breakSearch"),
                    "line": JSONValue(line),
                    "reason": JSONValue("endOfInterval"),
                    "maskInterval": JSONValue([bedBegin, bedEnd]),
                    "contigInterval": JSONValue([contig.begin, contig.end]),
                ]));
                break;
            }
            else if (contig.end < bedBegin)
            {
                continue;
            }
            else
            {
                auto interval = MaskInterval(
                    contigId,
                    max(bedBegin, contig.begin) - contig.begin,
                    min(bedEnd, contig.end) - contig.begin,
                );
                ++numSplitParts;

                if (options.cutoff <= interval.end - interval.begin)
                {
                    intervalsAcc ~= interval;
                    ++numMappedIntervals;
                }
                else
                {
                    logWarning(JSONValue([
                        "message": JSONValue("unmappedInterval"),
                        "reason": JSONValue("cutoff"),
                        "file": JSONValue(file),
                        "line": JSONValue(line),
                        "bedEntry": JSONValue(bedEntry),
                    ]));
                }
            }
        }

        if (numMappedIntervals == 0)
            logWarning(JSONValue([
                "message": JSONValue("unmappedInterval"),
                "reason": JSONValue("seeAbove"),
                "file": JSONValue(file),
                "line": JSONValue(line),
                "numTotalParts": JSONValue(numSplitParts),
                "numMappedParts": JSONValue(numMappedIntervals),
                "bedEntry": JSONValue(bedEntry),
            ]));
        else if (numMappedIntervals > 1)
            logDebug(JSONValue([
                "message": JSONValue("splitInterval"),
                "file": JSONValue(file),
                "line": JSONValue(line),
                "numTotalParts": JSONValue(numSplitParts),
                "numMappedParts": JSONValue(numMappedIntervals),
                "bedEntry": JSONValue(bedEntry),
            ]));
    }


    void convertDazzBedEntry(ref Appender!(MaskInterval[]) intervalsAcc, scope string[] bedEntry, string file, size_t line)
    {
        auto contigId = bedEntry[0].to!MaskHeaderEntry;
        auto bedBegin = bedEntry[1].to!MaskDataEntry;
        auto bedEnd = bedEntry[2].to!MaskDataEntry;

        enforce(0 < contigId, "invalid contig ID 0: contig IDs are 1-based");
        enforce(
            contigId <= contigs.length,
            format!"invalid contig ID %d: too large"(contigId),
        );

        auto contig = contigs[contigId - 1];

        enforce(
            0 <= bedBegin && bedBegin <= bedEnd && bedEnd <= contig.length,
            format!"contig coordinates [%d, %d) out of bounds: [0, %d]"(
                bedBegin,
                bedEnd,
                contig.length,
            ),
        );

        intervalsAcc ~= MaskInterval(
            contigId,
            bedBegin,
            bedEnd,
        );
    }


    void logWarning(JSONValue message)
    {
        stderr.writeln(message.toString);
    }


    void logDebug(JSONValue message)
    {
        if (options.verbose)
            stderr.writeln(message.toString);
    }
}


int main(string[] args)
{
    try
    {
        setProgram(args);
        auto options = parseOptions(args);
        auto converter = Bed2MaskConverter(cast(const) options);

        converter.run();
    }
    catch (Exception e)
    {
        stderr.writefln!"error: %s"(e);

        return 1;
    }

    return 0;
}
