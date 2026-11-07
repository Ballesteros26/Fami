/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

import com.appversion;
import com.util;
import ct.base;
import ct.purge;
import ct.dump;
import ct.build;
import ct.exporter;
import std.stdio;
import std.string;
import std.conv;
import std.file;

enum Command { None, ExportPRG, ExportSID, Dump, Import, Init }
const string[] exts = [ "", "prg", "sid", "s", "ct", "ct" ];

bool verbose = true;
bool noPurge;

Command resolveCt2utilCommand(string commandName) pure nothrow @safe {
	switch(commandName) {
	case "prg", "buildprg":
		return Command.ExportPRG;
	case "sid", "build":
		return Command.ExportSID;
	case "dump":
		return Command.Dump;
	case "import":
		return Command.Import;
	case "init":
		return Command.Init;
	default:
		return Command.None;
	}
}

void explain(string str) {
	if(verbose)
		writefln(str);
}

string defineOutfn(int cmd, string infn) {
	string name;
	int r = cast(int)(infn.lastIndexOf('.'));
	if(r <= 0) name = infn;
	else name = infn[0 .. infn.lastIndexOf('.')];
	return name ~ "." ~ exts[cmd];
}

bool doPurge(ref Song song) {
	if(noPurge) return true;
	explain("Purging data...");
	Purge p = new Purge(song, verbose);
	try {
		p.purgeAll();
	}
	catch(PurgeException e) {
		writeln(e);
		return false;
	}
	return true;
}

int main(string[] args) {
	int relocAddress = 0x1000, zpAddress = 0;

	// these two use PSID ranges (1..32)
	int defaultTune = 1, singleSubtune = -1;
	
	bool outfnDefined = false, infnDefined = false;
	int command;
	Song insong;
	string infn, outfn;
	string[3] infns;

	void printheader() {
		enum hdr = com.appversion.APP_DISPLAY_NAME ~ " utilities" ~
			com.util.buildInfo();
		writefln(hdr);
		writefln("\nUsage: \t%s <command> <options> <infile> <-o outfile>",args[0]);
		writefln("\t%s import <infile> <infile2> <-o outfile>",args[0]);
		writefln("\t%s init <binaryfile> <-o outfile>",args[0]);
		writefln("\nCommands:");
		writefln("  prg           Export song (.ct) to PRG file");
		writefln("  sid           Export song (.ct) to SID file");
		writefln("  dump          Dump song data to assembler source (BETA)");
		writefln("  import        Copy data from another song without overwriting the player");
		writefln("  init          Create a fresh .ct from player binary");
		writefln("\nGeneral options:");
		writefln("  -o <outfile>  Set output filename (by default gathered from input filename)");
		writefln("\nExport options:");
//		writefln("  -n            Do not purge before exporting/dumping (leaves unused data)");
		writefln("  -r <addr>     Relocate output to address (default = $1000)");
		writefln("  -d <num>      Set the default subtune (1-" ~ to!string(ct.base.SUBTUNE_MAX) ~ ")");
		writefln("  -s <num>      Export single subtune (1-" ~ to!string(ct.base.SUBTUNE_MAX) ~ ") (disables -d)");
		writefln("  -zp <num>     Relocate zero page (valid range 2-$fe)");
		writefln("  -q            Don't output information");
		writefln("\nPrefix value options with '0x' or '$' to indicate a hexadecimal value.");
	}

	if(args.length < 2) {
		printheader();
		return 0;
	}

	try {
		command = resolveCt2utilCommand(args[1]);
		if(command == Command.None)
			throw new UserException(format("command '%s' not recognized.",args[1]));
		int infncounter = 0;

		if(args.length >= 2) {
			for(int argp = 2; argp < args.length; argp++) {
				string nextArg() {
					if(argp+1 >= args.length || args[argp+1][0] == '-')
						throw new UserException("Missing value for option '" ~ args[argp] ~"'");
					argp++;
					return args[argp];
				}
				switch(args[argp]) {
				case "-n":
					noPurge = true;
					break;
				case "-r":
					if(command != Command.ExportSID &&
					   command != Command.ExportPRG)
						throw new UserException("Option available only with exporting commands.");
					int r = str2Value2(nextArg());
					if(r < 0x200 || r > 0xf900)
						throw new UserException("-r: reloc address out of range");
					relocAddress = cast(ushort)r;
					break;
				case "-s":
					if(command != Command.ExportSID &&
					   command != Command.ExportPRG)
						throw new UserException("Option available only with exporting commands.");
					int value = str2Value2(nextArg());
					if(value < 1 || value > ct.base.SUBTUNE_MAX)
						throw new UserException(format("Valid range for subtunes is 1 - %d.", ct.base.SUBTUNE_MAX));
					singleSubtune = value;
					break;
				case "-d":
					if(command != Command.ExportSID)
						throw new UserException("Option available only when exporting to SID.");
					defaultTune = str2Value2(nextArg());
					if(defaultTune < 1 || defaultTune > ct.base.SUBTUNE_MAX)
						throw new UserException(format("Valid range for subtunes is 1 - %d.", ct.base.SUBTUNE_MAX));
					break;
				case "-z", "-zp":
					if(command != Command.ExportSID &&
					   command != Command.ExportPRG)
						throw new UserException("Option available only with exporting commands.");
					zpAddress = str2Value2(nextArg());
					if(zpAddress < 2 || zpAddress > 0xfe) {
						throw new UserException("Valid range for zero page is 2 - $fe");
					}
					break;
				case "-o":
					if(outfnDefined)
						throw new UserException("Output file already defined.");
					outfn = args[argp+1];
					outfnDefined = true;
					argp++;
					break;
				case "-q":
					verbose = false;
					break;
				default:
					if(args[argp][0] == '-')
						throw new UserException("Unrecognized option '" ~ args[argp] ~ "'");
					if(infnDefined && command != Command.Import)
						throw new UserException("Input filename already defined. Use -o to define output file.");
					if(command == Command.Import) {
						if(infncounter > 1)
							throw new UserException("Infile & import filename already defined.");
						infns[infncounter++] = args[argp];
						infn = infns[0];
					}
					else infn = args[argp];
					infnDefined = true;
					break;
				}
			}
		}
		assert(command != Command.None);
		if(!infnDefined)
			throw new UserException("Input filename not defined.");
		if(command == Command.Init && !outfnDefined) {
			throw new UserException("Command 'init' requires output filename to be defined (option -o).");
		}
		else if(command == Command.Import && !outfnDefined) {
			throw new UserException("Command 'import' requires output filename to be defined (option -o).");
		}

		if(!outfnDefined) {
			outfn = defineOutfn(command, infn);
		}

		if(!std.file.exists(infn))
			throw new UserException(format("File %s does not exist", infn));

		explain("Input file: " ~ infn);
		explain("Output file: " ~ outfn);
		if(command == Command.ExportSID || command == Command.ExportPRG) {
			explain(format("Relocating data to $%x", relocAddress));
		}

		switch(command) {
		case Command.ExportPRG, Command.ExportSID:
			insong = new Song;
			insong.open(infn);
			ExportOptions options;
			options.relocAddress = relocAddress;
			options.zpAddress = zpAddress;
			options.defaultTune = defaultTune;
			options.singleSubtune = singleSubtune >= 1 ? singleSubtune : 0;
			options.skipPurge = noPurge;
			options.verbose = verbose;
			ubyte[] data;
			try {
				data = exportSong(insong,
					command == Command.ExportSID ? ExportFormat.SID : ExportFormat.PRG,
					options);
			}
			catch(Exception e) {
				writeln("error: ", e.msg);
				return -1;
			}
			std.file.write(outfn, data);
			break;
		case Command.Import:
			if(infncounter < 2)
				throw new UserException("Import song not defined.");
			explain("Importing data from " ~ infns[1]);
			insong = new Song;
			insong.open(infns[0]);
			Song importsong = new Song();
			importsong.open(infns[1]);
			insong.importData(importsong);
			insong.save(outfn);
			break;
		case Command.Dump:
			insong = new Song;
			insong.open(infn);
			doPurge(insong);
			string dumped = dumpOptimized(insong, 0x1000, 0, true,
										  verbose);
			string header = format(";;; ACME dump for %s\n\n", infn);
			std.file.write(outfn, header ~ dumped);
			break;
		case Command.Init:
			insong = new Song(cast(ubyte[])std.file.read(infn));
			insong.save(outfn);
			break;
		default:
			assert(0);
		}
	}
	catch(UserException e) {
		writeln("error: ", e);
		return -1;
	}
	catch(Exception e) {
		writeln(e);
		return -1;
	}
	scope(failure) {
		writeln("Aborted.");
	}
	scope(success) {
		explain("Done.");
	}
	return 0;
}
