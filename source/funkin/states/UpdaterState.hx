package funkin.states;

import flixel.util.FlxTimer;
import flixel.addons.display.FlxBackdrop;
import lime.system.System;
import haxe.io.Path;
import sys.io.File;
import sys.io.FileOutput;
import sys.FileSystem;
import openfl.utils.ByteArray;
import openfl.events.Event;
import openfl.events.ProgressEvent;
import openfl.net.URLRequest;
import openfl.net.URLLoader;
import flixel.ui.FlxBar;
import flixel.text.FlxText;
import flixel.util.FlxColor;

import funkin.api.Github;
import Main.Version;

using StringTools;

typedef DownloadData = {
	var fileName:String;
	var fileSize:Int;
	var link:String;
}

typedef FileData = {
	var fileName:String;
	var path:String;
}

typedef DLProgress = {
	var bytesFinished:Float;
	var bytesTotal:Float;
	var files:Array<DownloadData>;
	var downloadedFiles:Array<FileData>;
	var finishedFiles:Array<FileData>;
	var currentFile:Int;
	var totalFiles:Int;
	var done:Bool;
}

private function formatDecimal(Number:Float, Precision = 2):String {
	var mult:Float = 1;
	for (_ in 0...Precision)
		mult *= 10;
	
	var formatted = Std.string(Math.fround(Number * mult) / mult);
	var sowy = formatted.lastIndexOf('.');

	if (sowy == -1) {
		formatted += '.';
		sowy = 0;
	}else
		sowy = formatted.length - sowy - 1;

	for (_ in sowy...Precision)
		formatted += '0';

	return formatted;
}

private function formatBytes(Bytes:Float, Precision = 2):String {
	var units:Int = 0;
	while (Bytes >= 1024) {
		Bytes /= 1024;
		units++;
	}

	return formatDecimal(Bytes, Precision) + switch(units) {
		case 0: " Bytes";
		case 1: "kB";
		case 2: "MB";
		default: "GB";
	};
}

@:noScripting
class UpdaterState extends MusicBeatState {
	var busy:Bool = false;
	var updateText:FlxText;
	var controlsText:FlxText;
	var fileBar:FlxBar;

	static final path = Path.join([Sys.getEnv("TEMP"), "TrollEngineUpdate"]);
	static var OS(get, never):String;
	
	inline static function get_OS() {
		#if windows 
		return 'windows';
		#elseif mac
		return 'mac';
		#elseif linux
		return 'linux';		
		#end
	}

	var release:Release;
	var stream:URLLoader;
	var prog:DLProgress = {
		bytesFinished: 0,
		bytesTotal: 0,
		files: [],
		downloadedFiles: [],
		finishedFiles: [],
		currentFile: 0,
		totalFiles: 0,
		done: false
	}
	
	public function new(r:Release){
		super();
		release=r;
	}

	override function create(){
		var tuff = new FlxSprite();
		tuff.loadGraphic(Paths.image("week54prototype"));
		tuff.screenCenter();
		tuff.alpha = 0.6;
		add(tuff);

		var ac = new funkin.objects.shaders.AdjustColor();
		ac.brightness = -32 / 100;
		ac.contrast = 64 / 100;
		tuff.shader = ac.shader;

		/*
		var tile = new FlxBackdrop(Paths.image("trollface"), 16, 16);
		tile.antialiasing = false;
		tile.setGraphicSize(0, FlxG.height / 4 - tile.spacing.y);
		tile.updateHitbox();
		tile.blend = ADD;
		tile.alpha = 0.01;
		tile.velocity.x = tile.velocity.y = 10 * (FlxG.height / 720);
		tile.screenCenter(X);
		add(tile);
		*/

		////
		updateText = new FlxText(0, 0, FlxG.width);
		updateText.setFormat(Paths.font("calibrib.ttf"), 32, FlxColor.WHITE, CENTER);
		updateText.setBorderStyle(FlxTextBorderStyle.OUTLINE, FlxColor.BLACK, 4);
		add(updateText);

		fileBar = new FlxBar(0, 0, LEFT_TO_RIGHT, Std.int(FlxG.width/2), 10, null, null, 0, 100, false);
		fileBar.screenCenter(XY);
		fileBar.numDivisions = 200;
		fileBar.y += 100;
		fileBar.createFilledBar(FlxColor.GRAY, FlxColor.GREEN);
		fileBar.visible = false;
		add(fileBar);
		super.create();

		////
		if (release == null) {
			updateText.text = "grievous error";
			yesSelected = () -> gotoMenus();
			noSelected = yesSelected;
			ignoreSelected = yesSelected;
			return;
		}

		// TODO: Display release notes
		// trace(release.body);

		var beta = release.prerelease ? " (PRE-RELEASE)" : "";
		var currentBeta = Version.isBeta ? " (PRE-RELEASE)" : "";
		updateText.text = 'You are on Troll Engine v${Version.semanticVersion}${currentBeta}, but the most recent is v${release.tag_name}${beta}!';
		updateText.text += '\n\n[Y] Update • [N] Remind me later • [I] Skip this update';

		yesSelected = startDownload;
		noSelected = function() {
			FlxG.sound.play(Paths.sound('cancelMenu'));
			gotoMenus();
		}
		ignoreSelected = function() {
			FlxG.sound.play(Paths.sound('cancelMenu'));
			ignoreThisRelease();
		}
	}

	override function update(elapsed:Float){
		super.update(elapsed);
		updateText.screenCenter(Y);
		
		if (!busy) {	
			if (FlxG.keys.justPressed.N)
				noSelected();
			else if(FlxG.keys.justPressed.I)
				ignoreSelected();
			else if(FlxG.keys.justPressed.Y)
				yesSelected();
		}
	}

	function noop() {}

	dynamic function noSelected() {}
	dynamic function yesSelected() {}
	dynamic function ignoreSelected() {}

	dynamic function gotoMenus() {
		MusicBeatState.switchState(new TitleState());
	}

	////
	function ignoreThisRelease(playSound:Bool = true) {
		Main.outOfDate = false;
		
		FlxG.save.data.ignoredUpdates ??= [];
		FlxG.save.data.ignoredUpdates.push(release.tag_name);
		FlxG.save.flush();

		gotoMenus();
	}

	function startDownload() {		
		//// get every asset. there should probably only be 1 but y'know!!
		updateText.text = "Gathering files";

		var downloadList:Array<DownloadData> = [];

		for (asset in release.assets){
			if (asset.name.toLowerCase().contains(OS.toLowerCase())){
				downloadList.push({
					fileName: asset.name,
					link: asset.browser_download_url,
					fileSize: asset.size
				});
			}
		}

		if (downloadList.length == 0) {
			updateText.text = "Couldn't find platform-specific assets to download! :T\nPlease download the new version manually from GitHub";
			updateText.text += "\n\n[Y] Go to the release page • [N] Remind me later • [I] Skip this update";
			
			new FlxTimer().start(0.08, tmr -> {
				updateText.alpha = (tmr.elapsedLoops % 2 == 0) ? 1.0 : 0.6;
			}, 4);
			
			FlxG.sound.play(Paths.sound('scrollMenu')).pitch = 2;
			new FlxTimer().start(0.16, _ -> {
				FlxG.sound.play(Paths.sound('scrollMenu')).pitch = 2;
			}, 2);

			yesSelected = function() {
				FlxG.autoPause = true;
				FlxG.openURL(Main.recentRelease.html_url);
			};
			noSelected = function() {
				FlxG.sound.play(Paths.sound('cancelMenu'));
				gotoMenus();
			}
			ignoreSelected = function() {
				FlxG.sound.play(Paths.sound('cancelMenu'));
				ignoreThisRelease();
			}
			return;
			/*
			// If no platform-specific release then get every asset
			for (asset in release.assets) {
				downloadList.push({
					fileName: asset.name,
					link: asset.browser_download_url,
					fileSize: asset.size
				});
			}
			*/
		}

		//// setup folder to download to
		updateText.text = "Preparing";

		clearFiles(path);
		FileSystem.createDirectory(path);

		////
		updateText.text = "Starting download";

		prog.files = downloadList;
		prog.totalFiles += downloadList.length;

		busy = true;
		fileBar.visible = true;

		FlxG.autoPause = false;
		download(function(){
			fileBar.visible = false;
			updateText.text = "Finished downloading! Preparing extraction";
			sys.thread.Thread.create(() ->
			{ 
				installShit();
				updateText.text = "Finished extraction! Installing to the game folder..";

				var progPath = Path.normalize(Sys.programPath());
				var exeFile = Path.withoutDirectory(progPath);
				var programFolder = Path.directory(progPath);
				var finishedFolder = Path.join([path, 'Finished']);

				copy(finishedFolder, '', FileSystem.absolutePath(programFolder));
				updateText.text = "Done copying!";

				FileSystem.rename(progPath, Path.withExtension(progPath, 'tempcopy'));
				File.copy(Path.join([finishedFolder, exeFile]), progPath);
				prog.done = true; 
				
				clearFiles(path);

				var ret:Int = -1;

				#if windows
				ret = Sys.command('start', ['/B', exeFile]);
				#end
				
				if (ret == 0) {
					System.exit(0);
				}

				updateText.text = "It is now safe to close\nthis program";
				updateText.color = FlxColor.ORANGE;
			});
		});
	}

	function download(onFinish:Void->Void){
		var file = prog.files.shift();
		if(file==null){
			onFinish();
			return;
		}
		updateText.text = 'Beginning to download ${file.fileName} (${prog.currentFile} / ${prog.totalFiles})';
		// wanted to use a while loop to download everything, but can't cus of it being async so L
		downloadFile(file, download.bind(onFinish));
	}

	function downloadFile(file:DownloadData, onFinish:Void->Void){	  
		prog.bytesTotal = 1; // so no 0 / 0 bullshit
		prog.bytesFinished = 0; 
		fileBar.setRange(0, file.fileSize);
		stream = new URLLoader();
		stream.dataFormat = BINARY;
		stream.addEventListener(ProgressEvent.PROGRESS, function(e:ProgressEvent){
			prog.bytesFinished = e.bytesLoaded;
			prog.bytesTotal = e.bytesTotal;

			fileBar.setRange(0, prog.bytesTotal);
			fileBar.value = prog.bytesFinished;
			
			var finished = formatBytes(prog.bytesFinished);
			var total = formatBytes(prog.bytesTotal);
			updateText.text = 'Downloading ${file.fileName} ($finished / $total) (${prog.currentFile} / ${prog.totalFiles})';
		});
		stream.addEventListener(Event.COMPLETE, function(e:Event) {
			fileBar.percent = 100;
			prog.bytesFinished = prog.bytesTotal;
			var path = '$path\\${file.fileName}';
			var output:FileOutput = File.write(path);
			try{
				var writingData:ByteArray = new ByteArray();
				var downloadedData:ByteArray = stream.data;
				downloadedData.readBytes(writingData); // should read all bytes? if needed i'll stream it into the file output instead tho
				output.write(writingData); // should write all bytes? same as above if needed ill stream it
				prog.downloadedFiles.push({
					fileName: file.fileName,
					path: path
				});
			}catch(e:Dynamic){
				trace(file.fileName + " failed to write, RIP!! " + e);
			}
			output.flush();
			output.close();
			onFinish();

			prog.currentFile++;
		});

		stream.load(new URLRequest(file.link));
	}

	function installShit(){
		var extractionPath = '${path}\\Finished';
		clearFiles(extractionPath);
		FileSystem.createDirectory(extractionPath);

		prog.currentFile = 0;
		prog.totalFiles = prog.downloadedFiles.length;
		prog.bytesFinished = 0;
		prog.bytesTotal = 0;
		fileBar.setRange(0, prog.totalFiles);

		for (file in prog.downloadedFiles) {
			fileBar.value = prog.currentFile;

			if (!file.fileName.endsWith(".zip")) {
				prog.currentFile++;
				prog.finishedFiles.push(file);
				continue;
			}

			updateText.text = 'Reading file ${file.fileName} (${prog.currentFile} / ${prog.totalFiles})\nPlease wait';

			var toRead = File.read(file.path);
			var entries = haxe.zip.Reader.readZip(toRead);
			toRead.close();

			var extractedFiles:Int = 0;
			var totalFiles:Int = entries.length;
			updateText.text = 'Extracting (${prog.currentFile} / ${prog.totalFiles}) (${extractedFiles} / ${totalFiles})';

			for (zippedFile in entries) {
				updateText.text = 'Extracting (${prog.currentFile} / ${prog.totalFiles}) (${extractedFiles} / ${totalFiles})';
				extractedFiles++;

				var name = zippedFile.fileName;
				var fullPath = Path.join([extractionPath, name]);
				
				trace(name);
				
				if (name.endsWith("/")) {
					// dir
					if (!FileSystem.exists(fullPath))
						FileSystem.createDirectory(fullPath);
					else
						clearFiles(fullPath);
				}else{
					var directory = [for (w in name.split("/")) w.trim()];
					directory.pop();
					FileSystem.createDirectory(Path.join([extractionPath, directory.join("/")]));
					var data = haxe.zip.Reader.unzip(zippedFile);
					File.saveBytes(fullPath, data);
				}
			}

			prog.currentFile++;
		}
	}

	function copy(base:String, dir:String, dest:String){
		trace("copying from " + Path.join([base, dir]));
		for (file in FileSystem.readDirectory(Path.join([base, dir])))
		{
			var finFile = Path.join([base, dir, file]);
			var myFile = Path.join([dest, dir, file]);
			if (file.endsWith(".dll") || file.endsWith(".ndll"))
			{
				var temp = '${Path.withoutExtension(myFile)}.tempcopy';
				if(FileSystem.exists(temp))
					FileSystem.deleteFile(temp);
				FileSystem.rename(myFile, temp); // anything with the .temp ext will be removed after the game restarts
			}
			if (file == Path.withoutDirectory(Sys.programPath()))
			{
				trace("Ignoring copying the executable");
				continue;
			}
			if(file == 'content'){
				trace("Ignoring copying the content folder");
				// Maybe add a way to ask the user "Wanna replace the fuckin folders???"
				// And show a list of what content would be replaced with new content
				// This ensures that people who edit base game folder will be abl eto say no and keep their changes
				// rn tho, just skip content so we dont remove anyone's content folders

				/*
				no content should be distributed alongside the build!!!
				TODO: mods menu!!!!
				*/

				continue;
			}
			if (FileSystem.isDirectory(finFile)){
				if (FileSystem.exists(myFile) && !FileSystem.isDirectory(myFile)){
					FileSystem.deleteFile(myFile);
					trace("deletin da file " + myFile);
				}
				if (!FileSystem.exists(myFile)){
					trace("makin da directory " + myFile);
					FileSystem.createDirectory(myFile);
				}
				
				copy(base, Path.join([dir, file]), dest);
			}else{
				trace('Copying $finFile to $myFile');
				File.copy(finFile, myFile); 
			}
			
		}
	}

	function clearFiles(path:String){
		if (FileSystem.exists(path))
		{
			for (file in FileSystem.readDirectory(path))
			{
				var fp = Path.join([path, file]);
				if (FileSystem.isDirectory(fp)){
					clearFiles(fp);
					FileSystem.deleteDirectory(fp);
				}else
					FileSystem.deleteFile(fp);
			}
		}
	}

	#if(DO_AUTO_UPDATE || display)
	// gets the most recent release and returns it
	// if you dont have download betas on, then it'll exclude prereleases
	public static function getRecentGithubRelease():Release
	{
		var recentRelease:Release;

		if (ClientPrefs.checkForUpdates)
		{
			var github:Github = new Github(); // leaving the user and repo blank means it'll derive it from the repo the mod is compiled from
			// if it cant find the repo you compiled in, it'll just default to troll engine's repo
			recentRelease = github.getReleases((release:Release) -> (Main.downloadBetas || !release.prerelease))[0];
			
			if (recentRelease != null && FlxG.save.data.ignoredUpdates?.contains(recentRelease.tag_name) == true)
				recentRelease = null;
		}else{
			recentRelease = null;
		}

		return Main.recentRelease = recentRelease;
	}

	public static function checkOutOfDate():Bool{
		var outOfDate = false;

		if (!ClientPrefs.checkForUpdates) {
			trace('Update checking is disabled by the user');
		}
		else if (Main.recentRelease == null) {
			trace('No recent release found');
		}
		else {
			var recentRelease = Main.recentRelease;
			var tagName:funkin.data.SemanticVersion = recentRelease.tag_name;

			trace('Newest version: $tagName | Current: ${Version.semanticVersion}');
			
			// hoping this works lol
			if (tagName > Version.semanticVersion){
				outOfDate = true;
				trace('New version found!');
			}
		}

		return Main.outOfDate = outOfDate;
	}

	public static function clearTemps(dir:String)
	{
		#if desktop
		for (file in FileSystem.readDirectory(dir)){
			var file = './$dir/$file';
			if (FileSystem.isDirectory(file))
				clearTemps(file);
			else if (file.endsWith(".tempcopy"))
				FileSystem.deleteFile(file);
		}
		#end
	}
	#else
	public static function getRecentGithubRelease():Release
		return Main.recentRelease = null;

	public static function checkOutOfDate():Bool
		return Main.outOfDate = false;
	#end
}