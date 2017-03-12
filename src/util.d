import std.algorithm;
import std.conv;
import std.digest.crc;
import std.file;
import std.net.curl;
import std.path;
import std.regex;
import std.socket;
import std.stdio;
import std.string;

private string deviceName;

static this()
{
	deviceName = Socket.hostName;
}

// give a new name to the specified file or directory
void safeRename(const(char)[] path)
{
	auto ext = extension(path);
	auto newPath = path.chomp(ext) ~ "-" ~ deviceName;
	if (exists(newPath ~ ext)) {
		int n = 2;
		char[] newPath2;
		do {
			newPath2 = newPath ~ "-" ~ n.to!string;
			n++;
		} while (exists(newPath2 ~ ext));
		newPath = newPath2;
	}
	newPath ~= ext;
	rename(path, newPath);
}

// delete the specified file without throwing an exception if it does not exists
void safeRemove(const(char)[] path)
{
	if (exists(path)) remove(path);
}

// return the crc32 hex string of a file
string computeCrc32(string path)
{
	CRC32 crc;
	auto file = File(path, "rb");
	foreach (ubyte[] data; chunks(file, 4096)) {
		crc.put(data);
	}
	return crc.finish().toHexString().dup;
}

// convert wildcards (*, ?) to regex
Regex!char wild2regex(const(char)[] pattern)
{
	string str;
	str.reserve(pattern.length + 2);
	str ~= "^";
	foreach (c; pattern) {
		switch (c) {
		case '*':
			str ~= "[^/]*";
			break;
		case '.':
			str ~= "\\.";
			break;
		case '?':
			str ~= "[^/]";
			break;
		case '|':
			str ~= "$|^";
			break;
		default:
			str ~= c;
			break;
		}
	}
	str ~= "$";
	return regex(str, "i");
}

// return true if the network connection is available
bool testNetwork()
{
	HTTP http = HTTP("https://login.live.com");
	http.method = HTTP.Method.head;
	return http.perform(ThrowOnError.no) == 0;
}

// call globMatch for each string in pattern separated by '|'
bool multiGlobMatch(const(char)[] path, const(char)[] pattern)
{
	foreach (glob; pattern.split('|')) {
		if (globMatch!(std.path.CaseSensitive.yes)(path, glob)) {
			return true;
		}
	}
	return false;
}

// test if the given path is not included in the allowed paths
// if there are no allowed paths always return false
bool isPathExcluded(string path, string[] allowedPaths)
{
	// always allow the root
	if (path == ".") return false;
	// if there are no allowed paths always return false
	if (allowedPaths.empty) return false;

	path = buildNormalizedPath(path);
	foreach (allowed; allowedPaths) {
		auto comm = commonPrefix(path, allowed);
		if (comm.length == path.length || comm.length == allowed.length) {
			return false;
		}
	}
	return true;
}

unittest
{
	assert(multiGlobMatch(".hidden", ".*"));
	assert(multiGlobMatch(".hidden", "file|.*"));
	assert(!multiGlobMatch("foo.bar", "foo|bar"));
	assert(isPathExcluded("Documents2", ["Documents"]));
	assert(isPathExcluded("Hello/World", ["Hello/John"]));
	assert(!isPathExcluded("Documents", ["Documents"]));
	assert(!isPathExcluded("Documents/a.txt", ["Documents"]));
}
