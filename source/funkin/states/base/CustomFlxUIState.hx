package funkin.states.base;

#if flixel_ui
import flixel.addons.ui.FlxUICursor;
import flixel.addons.ui.FlxUITooltip;
import flixel.addons.ui.FlxUITooltipManager;
import flixel.addons.ui.interfaces.IEventGetter;
import flixel.addons.ui.interfaces.IFlxUIState;
import flixel.addons.ui.interfaces.IFireTongue;
import flixel.addons.ui.interfaces.IFlxUIWidget;
import flixel.addons.ui.interfaces.IFlxUIButton;

/**
	Not an extension of FlxUIState!
	Just a blank state that implements the ui interfaces to receive ui events, and to add tooltips.
	No flixel-ui xml features because none of the editors use those.  
**/
@:noScripting
class CustomFlxUIState extends MusicBeatState implements IEventGetter implements IFlxUIState {
	public function new() {
		super();
		tooltips = new FlxUITooltipManager();
		@:privateAccess tooltips.tooltip.visible = false;
	}

	override function tryUpdate(elapsed:Float):Void
	{
		super.tryUpdate(elapsed);
		if (tooltips != null) {
			@:privateAccess
			if (tooltips.tooltip != null && tooltips.tooltip.exists && tooltips.tooltip.active)
				tooltips.tooltip.update(elapsed);
			tooltips.update(elapsed);
		}
	}

	override function draw() {
		super.draw();
		@:privateAccess
		if (tooltips?.tooltip != null && tooltips.tooltip.exists && tooltips.tooltip.visible)
			tooltips.tooltip.draw();
	}

	override function destroy():Void
	{
		super.destroy();

		if (tooltips != null) {
			tooltips.destroy();
			tooltips = null;
		}
	}
	
	public function getEvent(name:String, sender:IFlxUIWidget, data:Dynamic, ?params:Array<Dynamic>):Void
	{
		return;
	}

	public function getRequest(name:String, sender:IFlxUIWidget, data:Dynamic, ?params:Array<Dynamic>):Dynamic
	{
		return null;
	}

	public function onShowTooltip(t:FlxUITooltip):Void
	{
		return;
	}

	public function forceFocus(b:Bool, thing:IFlxUIWidget):Void
	{
		return;
	}

	public var tooltips(default, null):FlxUITooltipManager;
	#if FLX_MOUSE
	public var cursor:FlxUICursor;
	#end
	private var _tongue:IFireTongue;
}
#end
