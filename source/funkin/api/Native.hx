package funkin.api;

import cpp.ConstCharStar;

@:include("filesystem")
extern class Native {
	inline static function getTempDirectory():ConstCharStar{
		#if mac
		return untyped Sys.getEnv("TMPDIR").c_str();
		#else
		return untyped __cpp__("std::filesystem::temp_directory_path().c_str()");
		#end
	}
}