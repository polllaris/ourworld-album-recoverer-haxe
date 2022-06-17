import sys.thread.Thread;
import tink.core.Promise.Recover;
import sys.io.File;
import sys.FileSystem;
import haxe.http.HttpBase;
import haxe.zip.Reader;
import sys.Http;
import haxe.Exception;
import haxe.io.Eof;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import Sys.print;
import Sys.println;
import Sys.stdout;
import Sys.stdin;
import Sys.sleep;
import sys.io.Process;
import Date;
import haxe.io.Eof;
import haxe.io.Encoding;
import de.polygonal.Printf;
import image.Image;
using tink.CoreApi;

class ProcessHelper {

    public static function runUntilEnd(cmd:String, args:Array<String>):String {
        /* run a process until it's finished and return stdout as a string */
        final proc:Process = new Process(cmd, args);
        proc.exitCode(true);
        return proc.stdout.readAll().toString();
    }

}

class DiskOption {

    public final name:String;
    public final identifier:String;

    public function new(name:String, identifier:String) {
        this.name = name;
        this.identifier = identifier;
    }

}

class DiskSelector {

    public static function readWmicLines(output:String):Array<String> {

        var lines:Array<String> = [];
        for (line in output.split("\r\r\n").slice(1)) {
            line = line.split("  ")[0];
            if (line != "") {
                lines.push(line);
            }
        }
        return lines;

    }

    public static function fetchDiskOptions():Array<DiskOption> {
 
        final names = readWmicLines(ProcessHelper.runUntilEnd("wmic", ["diskdrive", "get", "Caption"]));
        final identifiers = readWmicLines(ProcessHelper.runUntilEnd("wmic", ["diskdrive", "get", "DeviceID"]));
        final options:Array<DiskOption> = [];
        for (i in 0...identifiers.length) {
            options.push(new DiskOption(names[i], identifiers[i]));
        }

        return options;
    }
    public static function selectDiskOption():DiskOption {

        final options = fetchDiskOptions();
        options.reverse();
        var index = 0; for (option in options) {
            println('${index++}) ${option.identifier} ${option.name}');
        }
        print("\n");
        while(true) {
            print('please select the drive that ourWorld was played on i.e. option (0-${options.length - 1}): ');
            var number:Null<Int> = Std.parseInt(Sys.stdin().readLine());
            if (number != null && number >= 0 && number < options.length) {
                return options[number];
            }
        }

    }
}

class PhotorecDownloader {

    public static final photorecDownloadUrl = "https://www.cgsecurity.org/testdisk-7.2-WIP.win.zip";
    public static final extractName = "testdisk-7.2-WIP";

    public static function download():Bytes {

        var request = new haxe.Http(photorecDownloadUrl);
        request.request(false);
        return request.responseBytes;

    }

    public static function extract(data:Bytes):Void {
 
        final reader:Reader = new Reader(new BytesInput(data));
        for(entry in reader.read()) {
            var directories:Array<String> = entry.fileName.split("/").slice(0, -1);
            
            for (i in 0...directories.length+1) { // the directories.length + 1 which is actually the length because 0...10 would only go to 9
                var dirpath = directories.slice(0, i).join("/"); 
                if(!FileSystem.exists(dirpath)) {
                    FileSystem.createDirectory(dirpath);
                }
            }
            // I'm not sure how I feel about the fact that the entires are compressed in memory // one day later it makes sense stupid past me.
            if (entry.fileName.lastIndexOf("/") != (entry.fileName.length - 1)) {
                File.saveBytes(entry.fileName, Reader.unzip(entry));
            }
        }

    }
    public static function downloaded():Bool {

        // checks if photorec is downloaded and extracted
        return FileSystem.exists('${extractName}/photorec_win.exe');

    }
}

enum RecoveredCleanerAction {
    move_success;
    move_failure;
    delete_success;
    delete_failure;
}

class RecoveredCleanerStatus {

    public final action:RecoveredCleanerAction;
    public final fromPath:String;
    public final toPath:Null<String>;

    public function new(action:RecoveredCleanerAction, fromPath:String, ?toPath:Null<String>) {

        this.action = action;
        this.fromPath = fromPath;
        this.toPath = toPath;

    }

}
class RecoveredCleaner {
 
    public final photorecRecoveryPath:String;
    public final cleanedPlacementPath:String;
    public final deleteNonMatching:Bool;
    public var onAction:RecoveredCleanerStatus->Void;

    public function new(photorecRecoveryPath:String, cleanedPlacementPath:String, ?deleteNonMatching:Null<Bool>) {
        this.photorecRecoveryPath = photorecRecoveryPath;
        this.cleanedPlacementPath = cleanedPlacementPath;
        this.deleteNonMatching = (deleteNonMatching != null) ? deleteNonMatching : true;
        this.onAction = null;
    }

    public static function matchJpeg(path:String):Bool {

        var match:Bool;
        try {
            Image.getInfo(path).handle(function (outcome) switch outcome {
                case Success(info):
                    match = info.height == 475 && info.width == 633;
                default:
                    match = false;
            });
        } catch(e:Dynamic) {
            match = false;
        }
        return match;

    }

    public function clean() {

        final directories = [];
        // build a list of paths to directories that we aren't using for filtering
        for(filename in FileSystem.readDirectory(photorecRecoveryPath)) {
            var filepath = '${photorecRecoveryPath}/${filename}';
            if(FileSystem.isDirectory(filepath) && !StringTools.endsWith(filepath, "filtered")) {
                directories.push(filepath);
            }
        }
        // go through each directory and check if the jpegs match criteria with this.matchJpeg
        for(directory in directories) {
            for(filename in FileSystem.readDirectory(directory)) {
                var status:RecoveredCleanerStatus = null;
                var filepathOld = '${directory}/${filename}';
                var filepathNew =  '${cleanedPlacementPath}/${filename}';
                if (StringTools.endsWith(filepathOld, ".jpg") && matchJpeg(filepathOld)) {
                    try {
                        FileSystem.rename(filepathOld, filepathNew);
                        status = new RecoveredCleanerStatus(RecoveredCleanerAction.move_success, filepathOld, filepathNew);
                    } catch(e:Dynamic) {
                        status = new RecoveredCleanerStatus(RecoveredCleanerAction.move_failure, filepathOld, null);
                    }
                } else if (deleteNonMatching) {
                    try {
                        FileSystem.deleteFile(filepathOld);
                        status = new RecoveredCleanerStatus(RecoveredCleanerAction.delete_success, filepathOld, filepathNew);
                    } catch(e:Exception) {
                        status = new RecoveredCleanerStatus(RecoveredCleanerAction.delete_failure, filepathOld, null);
                    }

                }
                if (this.onAction != null && status != null) {
                    this.onAction(status);
                }
            }
        }

    }

}

class AlbumRecoverer {

    public final recoverDirPath:String;
    public final filteredDirPath:String;
    public final diskOption:DiskOption;
    public final photorecPath:String;

    public function new(
        recoverDirPath:String, filteredDirPath:String, 
        diskOption:DiskOption, photorecPath:String
    ) {
        this.recoverDirPath = recoverDirPath;
        this.filteredDirPath = filteredDirPath;
        this.diskOption = diskOption;
        this.photorecPath = photorecPath;
    }

    public static function main() {

        println(
            "Welcome to AlbumRecover (haxe) a small windows app to automate\n"+
            "downloading and using photorec to recover album photos.\n\n"+

            "how->it->works:\n\n"+

            "Your browser writes images that it loads to the disk cache,\n"+
            "when a file is deleted on a hard drive: the sectors to where\n"+
            "that file were are marked as being okay to write to, the next\n"+
            "files written to on the hard drive don't necessarily write to\n"+
            "the sectors that the \"deleted\" file was in right away.\n\n"+

            "The above means that in those sectors (assuming they haven't been\n"+
            "written to again yet) are the contents of the last file. That being said...\n"+
            "if you're going to \"undelete\" photos then it would be ideal to not write\n"+
            "them to the same disk that you're recovering them from as you risk them\n"+
            "being written in the places other files that you want to recover once were,\n\n"+

            "However... Provided that there's enough free space on the disk then this may be less\n"+
            "likely to happen and you should be able to recover all of not a majority of your photos regardless.\n\n"+

            "This application will recover photos to a directory relative to where it is, if you\n"+
            "launch it from a flash drive then things will be recovered to that flash drive. Happy Recovery ~ Jess\n\n"
        );

        Sys.print("Press enter to start...");
        Sys.stdin().readLine();

        // // check if photorec is downloaded and extracted and if it isn't then download and extract it
        if (!PhotorecDownloader.downloaded()) {
            println("photorec not found, attempting to download...");
            final response:Bytes = PhotorecDownloader.download();
            println("photorec downloaded to memory, attempting to extract...");
            PhotorecDownloader.extract(response);
            if(!PhotorecDownloader.downloaded()) {
                println("something went wrong with the extraction of photorec");
                Sys.exit(0);
            } else {
                println('photorec has been downloaded and extracted successfully to: ${PhotorecDownloader.extractName}');
            }
        }

        println("You will now need to select the drive that you've played ourWorld on.\n");

        final diskOption = DiskSelector.selectDiskOption();
        final recoverDirPath = 'recover-${Date.now().getTime()}';
        final filteredDirPath = '${recoverDirPath}/filtered';

        FileSystem.createDirectory(recoverDirPath);
        FileSystem.createDirectory(filteredDirPath);

        println('You have selected ${diskOption.identifier} ${diskOption.name}');

        final recoverer = new AlbumRecoverer(recoverDirPath, filteredDirPath, diskOption, '${PhotorecDownloader.extractName}/');
        recoverer.start();

    }

    public function start() {

        final cmd = 'cmd /c testdisk-7.2-WIP\\photorec_win.exe /d ${recoverDirPath}/ /cmd ${diskOption.identifier} partition_none,fileopt,everything,disable,jpg,enable,search,enable,wholedisk';
        final proc = new Process(cmd, null, false);

        var runThreadAlive = true;

        final runThread = Thread.create(() -> {
            proc.exitCode(true);
            runThreadAlive = false;
        });

        final cleaner = new RecoveredCleaner(recoverDirPath, filteredDirPath);
        cleaner.onAction = function(status:RecoveredCleanerStatus) {
            var action:String;
            var from:String = status.fromPath; 
            var state:String;
            if (status.action == RecoveredCleanerAction.move_success || status.action == RecoveredCleanerAction.move_failure) {
                action = "move";
                state = (status.action == RecoveredCleanerAction.move_success) ? status.toPath : "fail";
            } else if (status.action == RecoveredCleanerAction.delete_success || status.action == RecoveredCleanerAction.delete_failure) {
                action = "delete";
                state = (status.action == RecoveredCleanerAction.delete_success) ? "success" : "fail";
            } else {
                return;
            }
            println(Printf.format("%-8s %-45s %-42s", [action, from, state]));
        }
        println(Printf.format("%-8s %-45s %-42s", ["action", "from", "state"]));
        while(runThreadAlive) {
            cleaner.clean();
            Sys.sleep(5);
        }

        print("\n");
        println("Photorec has terminated, assuming that it finished successfully you can");
        print("press enter to go to the recovered album photos...");
        Sys.stdin().readLine();

        // replace / with \\ because windows uses / for arguments and \ for filepaths.
        var windowsPath = StringTools.replace(filteredDirPath, "/", "\\");
        // open explorer with the path to the directory containing the album photos
        Sys.command('explorer.exe ${windowsPath}');

    }
}
