import flash.accessibility.Accessibility;
import flash.events.MouseEvent;
import flash.external.ExternalInterface;
import flash.utils.Timer;

class Player {
    var reconnectTimer : Timer;
	var volume    : Float;
	var tracker   : Tracker;
	var ui        : UI;
	var streamUrl     : String;
	var fallbackUrl   : String;
	var introUrl      : String;
	var fileextension : String;
	var playing   : Bool;
	var buffering : Int;
	var playBuffer: Bool;
	var reportBufferingEventTimer : Timer;
	var lastBufferingState : Bool;
	var introPlayer : IntroPlayer;
	var errorCount : Int;
    var request   : flash.net.URLRequest;
	var soundObject : flash.events.IEventDispatcher;

	private function new(ui:UI,url:String,tracker:Tracker,fallbackUrl:String,introUrl:String){
		this.ui=ui;
		this.introUrl = introUrl;
		playBuffer = false;
		playing = false;
		this.volume = 1;
		this.streamUrl=url;
        this.fallbackUrl = fallbackUrl;
		this.errorCount=0;
		lastBufferingState = false;
		this.tracker=tracker;
		if(fileextension==null){
			fileextension="mp3";
		}
		reportBufferingEventTimer = new Timer(100);
		reportBufferingEventTimer.addEventListener(flash.events.TimerEvent.TIMER, reportBufferingEvent);
		reportBufferingEventTimer.start();
		introPlayer = new IntroPlayer(introUrl, this);
		ui.informIntroUrl(introUrl);
		flash.external.ExternalInterface.addCallback('stopSound', jsStopSound);
		flash.external.ExternalInterface.addCallback('playSound', jsPlaySound);
		flash.external.ExternalInterface.addCallback('setVolume', setVolume);
		flash.external.ExternalInterface.addCallback('setUrl', setUrl);
		flash.external.ExternalInterface.addCallback('setFallbackUrl', setFallbackUrl);
		flash.external.ExternalInterface.addCallback('setTitle', setTitle);
	}

	function isBuffering():Bool { return false; }
	function createSoundObject(){}
	function closeSound() {}
	function forceSynchronization() {}
	function loadSound(request:flash.net.URLRequest){}
	function startSound(){}
	private function updateVolume(){}
	private function setMetadata(e:MetadataEvent){}
	
	public function stop(){
		closeSound();
		Reflect.deleteField(this,'request');
		request=null;
		ui.setStatus(FFMp3PlayerStatus.stop);
		playBuffer=false;
	}
	
	function soundLength():Float{
		return 0;
	}
	
	private function getUrl():String{
		var antiCacheParameters="?"+Date.now().getTime()+"."+fileextension;
		return getCurrentUrl()+antiCacheParameters;
	}
	
	public function setUrl(url : String) {
		this.streamUrl = url;
	}
	
	public function setFallbackUrl(fallbackUrl : String) {
		this.fallbackUrl = fallbackUrl;
	}
	
	public function setTitle(title : String) {
		ui.setDefaultTitle(title);
		ui.resetTitle();
	}
	
	public function getCurrentUrl():String {
		if (this.fallbackUrl == null || this.errorCount % 2 == 0) {
			ui.informSource(streamUrl, false);
			return streamUrl;
		}
		ui.informSource(fallbackUrl, true);
		return fallbackUrl;
	}
	
    // Play button clicked, play the music
	
    public function playSound(e = null) {
		if(e!=null && e.type==flash.events.MouseEvent.CLICK){
			introPlayer.startSound();
			return;
		}
		if(playing){
			return;
		}
		playing=true;
		setReconnectTimer();
		
		// If there's a sound
		playBuffer=true; 
		stop();
		soundObject = null;

		var url = getUrl();
		// If there's a url
		if (url != null){
			tracker.track(getCurrentUrl(),true);
			// If no sound object, create one
			if (soundObject == null){
				request = new flash.net.URLRequest(url);
				createSoundObject();
				// Add the event listeners for errors
				soundObject.addEventListener(flash.events.IOErrorEvent.IO_ERROR, ioError);
				soundObject.addEventListener(flash.events.SecurityErrorEvent.SECURITY_ERROR, securityError);
				loadSound(request);
				// Set the position to the start because this is the first time
			}
			// Play the music
			if (soundObject != null){
				// Add the event listeners for load progress, load
				// complete and sound open
				soundObject.addEventListener(flash.events.Event.COMPLETE, loadComplete);
				soundObject.addEventListener(flash.events.Event.OPEN, soundOpen);
				// Play the music, this will return null the first
				// time around because not enough data available
				startSound();
				updateVolume();
				// Set the text to show what's happening
				ui.setStatus(FFMp3PlayerStatus.play);
			}
		}
    }
	
    // Load complete event
    public function loadComplete(e){
		// Show what's happening
		ui.setStatus(FFMp3PlayerStatus.loadComplete);
		reconnect(null);
		this.errorCount++;
    }

	function soundOpen(e : OpenEvent){
		updateVolume();
    }	
	
	// Stop button clicked
    public function stopSound(e=null){
		stopReconnectTimer();
		if(e!=null && e.type==flash.events.MouseEvent.CLICK ){
			introPlayer.stopSound();
		}
		stop();
		playing=false;
    }
	
	// Stop by js
	public function jsStopSound() {
		stopSound(new MouseEvent(MouseEvent.CLICK));
	}
	
	// Play by js
	public function jsPlaySound() {
		playSound(new MouseEvent(MouseEvent.CLICK));
	}
	
    // IO error
    public function ioError(e : flash.events.Event ){
		playBuffer=true;
		stop();
		ui.setStatus(FFMp3PlayerStatus.ioError);
		setReconnectTimer(3);
		this.errorCount++;
    }
	
	// Security Error (missing or restrictive crossdomain.xml)
	public function securityError(e : flash.events.Event ){
		playBuffer=true;
		stop();
		// Show the error
		ui.setStatus(FFMp3PlayerStatus.securityError);	
		setReconnectTimer(3);
		this.errorCount++;
    }

    // Volume change event
    public function changeVolume(e : ValueChangeEvent){
		// Set the new volume
		this.volume = e.value;
		updateVolume();
		// Show what's happening
		ui.setVolume(volume);
		introPlayer.setVolume(volume);
    }		

    // set audio volume via the user interface
    public function setVolume(volume : Float){
		ui.volumeControl.setVolume(volume);
    }
	
	// Reconect
	public function reconnect(e){
		playBuffer=true;
		stopSound(e);
		playSound(e);
	}	

	// Set the reconnection timer in case of error
	public function setReconnectTimer(time:Int = 0){
		// If there's a timer, stop it
		this.stopReconnectTimer();
		if(time==0){
			time=1800;
		}
		// Create a new timer, 2 secs
		reconnectTimer = new Timer(2000*time, 1);
		reconnectTimer.addEventListener(flash.events.TimerEvent.TIMER, reconnect);
		reconnectTimer.start();		
	}
	
	// Stop the reconnection timer
	public function stopReconnectTimer(){
		if (reconnectTimer != null){
			reconnectTimer.stop();
		}
	}
	
	// Set buffering time
	public function setBuffering(b:Int){
		buffering=b;
	}

	function reportBufferingEvent(e=null){
		var ib:Bool=isBuffering();
		if(lastBufferingState != ib){
			if(ib){
				ui.setStatus(FFMp3PlayerStatus.buffering);
			}else if(this.playing){
				ui.setStatus(FFMp3PlayerStatus.play);
				forceSynchronization();
			}
			lastBufferingState=ib;
		}
	}
	
	//
	public function isPlaying() : Bool {
		return playing;
	}
		
	public function reportIntro() {
		ui.setStatus(FFMp3PlayerStatus.intro, false);
		ui.informIntroUrl(this.introUrl);
	}
}