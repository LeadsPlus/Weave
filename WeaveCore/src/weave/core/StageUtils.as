/*
    Weave (Web-based Analysis and Visualization Environment)
    Copyright (C) 2008-2011 University of Massachusetts Lowell

    This file is a part of Weave.

    Weave is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License, Version 3,
    as published by the Free Software Foundation.

    Weave is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Weave.  If not, see <http://www.gnu.org/licenses/>.
*/

package weave.core
{
	import flash.display.Stage;
	import flash.events.Event;
	import flash.events.KeyboardEvent;
	import flash.events.MouseEvent;
	import flash.events.TimerEvent;
	import flash.geom.Point;
	import flash.utils.Dictionary;
	import flash.utils.Timer;
	import flash.utils.getTimer;
	
	import mx.core.UIComponentGlobals;
	import mx.core.mx_internal;
	
	import weave.api.WeaveAPI;
	import weave.api.core.ICallbackCollection;
	import weave.api.core.IStageUtils;
	import weave.api.newLinkableChild;
	import weave.api.reportError;
	import weave.compiler.StandardLib;
	import weave.utils.DebugTimer;
	
	use namespace mx_internal;
	
	/**
	 * This allows you to add callbacks that will be called when an event occurs on the stage.
	 * 
	 * WARNING: These callbacks will trigger on every mouse and keyboard event that occurs on the stage.
	 *          Developers should not add any callbacks that run computationally expensive code.
	 * 
	 * @author adufilie
	 */
	public class StageUtils implements IStageUtils
	{
		[Bindable] public var enableThreadPriorities:Boolean = false;
		
		private const frameTimes:Array = [];
		private var debug_fps:Boolean = false;
		
		public function StageUtils()
		{
			initialize();
		}
		
		/**
		 * This is the last keyboard event that occurred on the stage.
		 * This variable is set while callbacks are running and is cleared immediately after.
		 */
		public function get keyboardEvent():KeyboardEvent
		{
			return _event as KeyboardEvent;
		}
		/**
		 * This is the last mouse event that occurred on the stage.
		 * This variable is set while callbacks are running and is cleared immediately after.
		 */
		public function get mouseEvent():MouseEvent
		{
			return _event as MouseEvent;
		}
		/**
		 * This is the last event that occurred on the stage.
		 * This variable is set while callbacks are running and is cleared immediately after.
		 */
		public function get event():Event
		{
			return _event as Event;
		}
		private var _event:Event = null; // returned by get event()
		
		/**
		 * @return The current pressed state of the ctrl key.
		 */
		public function get shiftKey():Boolean
		{
			return _shiftKey;
		}
		private var _shiftKey:Boolean = false; // returned by get shiftKey()
		/**
		 * @return The current pressed state of the ctrl key.
		 */
		public function get altKey():Boolean
		{
			return _altKey;
		}
		private var _altKey:Boolean = false; // returned by get altKey()
		/**
		 * @return The current pressed state of the ctrl key.
		 */
		public function get ctrlKey():Boolean
		{
			return _ctrlKey;
		}
		private var _ctrlKey:Boolean = false; // returned by get ctrlKey()
		
		/**
		 * @return The current pressed state of the mouse button.
		 */
		public function get mouseButtonDown():Boolean
		{
			return _mouseButtonDown;
		}
		private var _mouseButtonDown:Boolean = false; // returned by get mouseButtonDown()
		
		/**
		 * @return true if the mouse moved since the last frame.
		 */
		public function get mouseMoved():Boolean
		{
			if (!_stage)
				return false;
			return _stage.mouseX != _lastMousePoint.x || _stage.mouseY != _lastMousePoint.y;
		}
		
		/**
		 * This is the total time it took to process the previous frame.
		 */
		public function get previousFrameElapsedTime():int
		{
			return _previousFrameElapsedTime;
		}
		
		/**
		 * This is the amount of time the current frame has taken to process so far.
		 */
		public function get currentFrameElapsedTime():int
		{
			return getTimer() - _currentFrameStartTime;
		}
		
		/**
		 * When the current frame elapsed time reaches this threshold, callLater processing will be done in later frames.
		 */
		[Bindable] public var maxComputationTimePerFrame:uint = 100;
		
		/**
		 * This function gets called on ENTER_FRAME events.
		 */
		private function handleEnterFrame():void
		{
			var currentTime:int = getTimer();
			_previousFrameElapsedTime = currentTime - _currentFrameStartTime;
			_currentFrameStartTime = currentTime;
			if (maxComputationTimePerFrame == 0)
				maxComputationTimePerFrame = 100;
			
			if (debug_fps)
			{
				frameTimes.push(previousFrameElapsedTime);
				if (frameTimes.length == 24)
				{
					trace(Math.round(1000 / StandardLib.mean.apply(null, frameTimes)),'fps; max computation time',maxComputationTimePerFrame);
					frameTimes.length = 0;
				}
			}
			
			if (_previousFrameElapsedTime > 3000)
				trace(_previousFrameElapsedTime);
			
			// update mouse coordinates
			_lastMousePoint.x = _stage.mouseX;
			_lastMousePoint.y = _stage.mouseY;
			
			var args:Array;
			var stackTrace:String;
			var calls:Array;
			var i:int;

			// first run the functions that cannot be delayed more than one frame.
			if (_callNextFrameArray.length > 0)
			{
				calls = _callNextFrameArray;
				_callNextFrameArray = [];
				for (i = 0; i < calls.length; i++)
				{
					// args: (relevantContext:Object, method:Function, parameters:Array = null, allowMultipleFrameDelay:Boolean = true)
					args = calls[i] as Array;
					stackTrace = _stackTraceMap[args];
					// don't call the function if the relevantContext was disposed of.
					if (!WeaveAPI.SessionManager.objectWasDisposed(args[0]))
						(args[1] as Function).apply(null, args[2]);
				}
			}
			
			if (_callLaterArray.length > 0 && UIComponentGlobals.callLaterSuspendCount <= 0)
			{
				//trace("handle ENTER_FRAME, " + _callLaterArray.length + " callLater functions, " + currentFrameElapsedTime + " ms elapsed this frame");
				// Make a copy of the function calls and clear the private array before executing any functions.
				// This allows the private array to be filled up as a result of executing the functions,
				// and prevents from newly added functions from being called until the next frame.
				calls = _callLaterArray;
				_callLaterArray = [];
				var stopTime:int = _currentFrameStartTime + maxComputationTimePerFrame;
				for (i = 0; i < calls.length; i++)
				{
					// if elapsed time reaches threshold, call everything else later
					if (getTimer() > stopTime)
					{
						// To preserve the order they were added, put the remaining callLater
						// functions for this frame in front of any others that may have been added.
						var j:int = calls.length;
						while (--j >= i)
							_callLaterArray.unshift(calls[j]);
						break;
					}
					// args: (relevantContext:Object, method:Function, parameters:Array = null, allowMultipleFrameDelay:Boolean = true)
					args = calls[i] as Array;
					stackTrace = _stackTraceMap[args]; // check this for debugging where the call came from
					// don't call the function if the relevantContext was disposed of.
					if (!WeaveAPI.SessionManager.objectWasDisposed(args[0]))
					{
						// TODO: PROFILING: check how long this function takes to execute.
						// if it takes a long time (> 1000 ms), something's wrong...
						
						(args[1] as Function).apply(null, args[2]);
					}
				}
			}
		}
		private var _currentFrameStartTime:int = getTimer(); // this is the result of getTimer() on the last ENTER_FRAME event.
		private var _previousFrameElapsedTime:int = 0; // this is the amount of time it took to process the previous frame.
		
		/**
		 * This calls a function in a future ENTER_FRAME event.  The function call will be delayed
		 * further frames if the maxComputationTimePerFrame time limit is reached in a given frame.
		 * @param relevantContext This parameter may be null.  If the relevantContext object gets disposed of, the specified method will not be called.
		 * @param method The function to call later.
		 * @param parameters The parameters to pass to the function.
		 */
		public function callLater(relevantContext:Object, method:Function, parameters:Array = null, allowMultipleFrameDelay:Boolean = true):void
		{
			//trace("call later @",currentFrameElapsedTime);
			if (allowMultipleFrameDelay)
				_callLaterArray.push(arguments);
			else
				_callNextFrameArray.push(arguments);
			
			if (CallbackCollection.debug)
				_stackTraceMap[arguments] = new Error("Stack trace").getStackTrace();
		}
		
		private const _stackTraceMap:Dictionary = new Dictionary(true);
		
		/**
		 * This is an array of functions with parameters that will be executed the next time handleEnterFrame() is called.
		 * This array gets populated by callLater().
		 */
		private var _callNextFrameArray:Array = [];
		
		/**
		 * This is an array of functions with parameters that will be executed the next time handleEnterFrame() is called.
		 * This array gets populated by callLater().
		 */
		private var _callLaterArray:Array = [];
		
		/**
		 * This will start an asynchronous task, calling iterativeTask() across multiple frames until it returns a value of 1 or the relevantContext object is disposed of.
		 * @param relevantContext This parameter may be null.  If the relevantContext object gets disposed of, the task will no longer be iterated.
		 * @param iterativeTask A function that performs a single iteration of the asynchronous task.
		 *   This function must take no parameters and return a number from 0.0 to 1.0 indicating the overall progress of the task.
		 *   A number below 1.0 indicates that the function should be called again to continue the task.
		 *   When the task is completed, iterativeTask() should return 1.0.
		 *   Example:
		 *       var array:Array = ['a','b','c','d'];
		 *       var index:int = 0;
		 *       function iterativeTask():Number
		 *       {
		 *           if (index >= array.length) // in case the length is zero
		 *               return 1;
		 * 
		 *           trace(array[index]);
		 * 
		 *           index++;
		 *           return index / array.length;  // this will return 1.0 on the last iteration.
		 *       }
		 * @param priority The task priority, which should be one of the static constants in WeaveAPI.
		 * @see weave.api.WeaveAPI
		 */
		public function startTask(relevantContext:Object, iterativeTask:Function, priority:int):void
		{
			// do nothing if task already active
			if (WeaveAPI.ProgressIndicator.hasTask(iterativeTask))
				return;
			
			if (priority == WeaveAPI.TASK_PRIORITY_RENDERING && !enableThreadPriorities)
			{
				while (iterativeTask() < 1) { }
				return;
			}
			
			if (priority <= 0)
			{
				reportError("Task priority " + priority + " is not supported.");
				priority = WeaveAPI.TASK_PRIORITY_BUILDING;
			}
			
			WeaveAPI.ProgressIndicator.addTask(iterativeTask);
			
			_iterateTask(relevantContext, iterativeTask, priority);
		}
		
		public var debug_delayTasks:Boolean = false;
		
		/**
		 * @private
		 */
		private function _iterateTask(context:Object, task:Function, priority:int):void
		{
			// remove the task if the context was disposed of
			if (WeaveAPI.SessionManager.objectWasDisposed(context))
			{
				WeaveAPI.ProgressIndicator.removeTask(task);
				return;
			}
			
			var stopTime:int;
			if (enableThreadPriorities)
				stopTime = _currentFrameStartTime + maxComputationTimePerFrame / priority;
			else
				stopTime = _currentFrameStartTime + 100;
			
			var progress:* = undefined;
			// iterate on the task until stopTime is reached
			while (getTimer() < stopTime)
			{
				// perform the next iteration of the task
				progress = task() as Number;
				if (progress === null || isNaN(progress) || progress < 0 || progress > 1)
				{
					reportError("Received unexpected result from iterative task (" + progress + ").  Expecting a number between 0 and 1.  Task cancelled.");
					progress = 1;
				}
				if (progress == 1)
				{
					// task is done, so remove the task
					WeaveAPI.ProgressIndicator.removeTask(task);
					return;
				}
				if (debug_delayTasks)
					break;
			}
			// max computation time reached without finishing the task, so update the progress indicator and continue the task later
			if (progress !== undefined)
				WeaveAPI.ProgressIndicator.updateTask(task, progress);
			
			// Set relevantContext as null for callLater because we always want _iterateTask to be called later.
			// This makes sure that the task is removed when the actual context is disposed of.
			callLater(null, _iterateTask, arguments);
		}
		
		
		/**
		 * This function gets called when a mouse click event occurs.
		 */
		private function handleMouseDown():void
		{
			// remember the mouse down point for handling POINT_CLICK_EVENT callbacks.
			_lastMouseDownPoint.x = mouseEvent.stageX;
			_lastMouseDownPoint.y = mouseEvent.stageY;
		}
		/**
		 * This function gets called when a mouse click event occurs.
		 */
		private function handleMouseClick():void
		{
			// if the mouse down point is the same as the mouse click point, trigger the POINT_CLICK_EVENT callbacks.
			if (_lastMouseDownPoint.x == mouseEvent.stageX && _lastMouseDownPoint.y == mouseEvent.stageY)
			{
				var cc:ICallbackCollection = _callbackCollections[POINT_CLICK_EVENT] as ICallbackCollection;
				cc.triggerCallbacks();
				cc.resumeCallbacks(true);
			}
		}
		
		/**
		 * This is a list of eventType Strings that can be passed to addEventCallback().
		 * @return An Array of Strings.
		 */
		public function getSupportedEventTypes():Array
		{
			return _eventTypes.concat();
		}
		
		/**
		 * This is a list of supported event types.
		 */
		private const _eventTypes:Array = [ 
				POINT_CLICK_EVENT,
				Event.ACTIVATE, Event.DEACTIVATE,
				MouseEvent.CLICK, MouseEvent.DOUBLE_CLICK,
				MouseEvent.MOUSE_DOWN, MouseEvent.MOUSE_MOVE,
				MouseEvent.MOUSE_OUT, MouseEvent.MOUSE_OVER,
				MouseEvent.MOUSE_UP, MouseEvent.MOUSE_WHEEL,
				MouseEvent.ROLL_OUT, MouseEvent.ROLL_OVER,
				KeyboardEvent.KEY_DOWN, KeyboardEvent.KEY_UP,
				Event.ENTER_FRAME, Event.FRAME_CONSTRUCTED, Event.EXIT_FRAME, Event.RENDER
			];
		private var _callbackCollectionsInitialized:Boolean = false; // This is true after the callback collections have been created.
		private var _listenersInitialized:Boolean = false; // This is true after the mouse listeners have been added.
		
		/**
		 * This timer is only used if initialize() is attempted before the stage is accessible.
		 */
		private const _initializeTimer:Timer = new Timer(0, 1);

		/**
		 * This is a mapping from an event type to a callback collection associated with it.
		 */
		private const _callbackCollections:Object = {};
		
		/**
		 * initialize callback collections.
		 */
		private function initialize(event:TimerEvent = null):void
		{
			var type:String;
			
			// initialize callback collections if not done so already
			if (!_callbackCollectionsInitialized)
			{
				// create a new callback collection for each type of event
				for each (type in _eventTypes)
				{
					_callbackCollections[type] = new CallbackCollection();
				}
				
				// set this flag so callback collections won't be initialized again
				_callbackCollectionsInitialized = true;
				
				// add these callbacks now so they will execute before any others
				addEventCallback(Event.ENTER_FRAME, null, handleEnterFrame);
				addEventCallback(MouseEvent.MOUSE_DOWN, null, handleMouseDown);
				addEventCallback(MouseEvent.CLICK, null, handleMouseClick);
			}
			
			// initialize the mouse event listeners if possible and necessary
			if (!_listenersInitialized && WeaveAPI.topLevelApplication != null && WeaveAPI.topLevelApplication.stage != null)
			{
				// save a pointer to the stage.
				_stage = WeaveAPI.topLevelApplication.stage;
				// create listeners for each type of event
				for each (type in _eventTypes)
				{
					// do not create event listeners for POINT_CLICK_EVENT because it is not a real event
					if (type == POINT_CLICK_EVENT)
						continue;
					
					generateListeners(type);
				}
				_listenersInitialized = true;
			}
			
			// check again if listeners have been initialized
			if (!_listenersInitialized)
			{
				// if initialize() can't be done yet, start a timer so initialize() will be called later.
				_initializeTimer.addEventListener(TimerEvent.TIMER_COMPLETE, initialize);
				_initializeTimer.start();
			}
		}
		/**
		 * This is for internal use only.
		 * These inline functions are generated inside this function to avoid re-use of local variables.
		 * @param eventType An event type to generate a listener function for.
		 * @return An event listener function for the given eventType that updates the event variables and runs event callbacks.
		 */
		private function generateListeners(eventType:String):void
		{
			var cc:ICallbackCollection = _callbackCollections[eventType] as ICallbackCollection;

			var captureListener:Function = function (event:Event):void
			{
				// set event variables
				_event = event;
				var mouseEvent:MouseEvent = event as MouseEvent;
				if (mouseEvent)
				{
					// Ignore this event if stageX is undefined.
					// It seems that whenever we get a mouse event with undefined coordinates,
					// we always get a duplicate event right after that defines the coordinates.
					// The ctrlKey,altKey,shiftKey properties always seem to be false when the coordinates are NaN.
					if (isNaN(mouseEvent.stageX))
						return; // do nothing when coords are undefined
					
					_altKey = mouseEvent.altKey;
					_shiftKey = mouseEvent.shiftKey;
					_ctrlKey = mouseEvent.ctrlKey;
					_mouseButtonDown = mouseEvent.buttonDown;
				}
				var keyboardEvent:KeyboardEvent = event as KeyboardEvent;
				if (keyboardEvent)
				{
					_altKey = keyboardEvent.altKey;
					_shiftKey = keyboardEvent.shiftKey;
					_ctrlKey = keyboardEvent.ctrlKey;
				}
				// run callbacks for this event type
				cc.triggerCallbacks();
				// clear _event variable
				_event = null;
			};
			
			var stageListener:Function = function(event:Event):void
			{
				if (event.target == _stage)
					captureListener(event);
			};
			
			_generatedListeners.push(captureListener, stageListener);
			
			// Add a listener to the capture phase so the callbacks will run before the target gets the event.
			_stage.addEventListener(eventType, captureListener, true, 0, true); // use capture phase
			
			// If the target is the stage, the capture listener won't be called, so add
			// an additional listener that runs callbacks when the stage is the target.
			_stage.addEventListener(eventType, stageListener, false, 0, true); // do not use capture phase
		}
		
		/**
		 * This Array is used to keep strong references to the generated listeners so that they can be added with weak references.
		 * The weak references only matter when this code is loaded as a sub-application and later unloaded.
		 */		
		private const _generatedListeners:Array = [];
		
		/**
		 * WARNING: These callbacks will trigger on every mouse event that occurs on the stage.
		 *          Developers should not add any callbacks that run computationally expensive code.
		 * 
		 * This function will add the given function as a callback.  The function must not require any parameters.
		 * @param eventType The name of the event to add a callback for.
		 * @param callback The function to call when an event of the specified type is dispatched from the stage.
		 * @param runCallbackNow If this is set to true, the callback will be run immediately after it is added.
		 */
		public function addEventCallback(eventType:String, relevantContext:Object, callback:Function, runCallbackNow:Boolean = false):void
		{
			var cc:ICallbackCollection = _callbackCollections[eventType] as ICallbackCollection;
			if (cc != null)
			{
				cc.addImmediateCallback(relevantContext, callback, runCallbackNow);
			}
			else
			{
				reportError("(StageUtils) Unsupported event: "+eventType);
			}
		}
		
		/**
		 * @param eventType The name of the event to remove a callback for.
		 * @param callback The function to remove from the list of callbacks.
		 */
		public function removeEventCallback(eventType:String, callback:Function):void
		{
			var cc:ICallbackCollection = _callbackCollections[eventType] as ICallbackCollection;
			if (cc != null)
				cc.removeCallback(callback);
		}

		/**
		 * This is a pointer to the stage.  This is null until initialize() is successfully called.
		 */
		private var _stage:Stage = null;
		
		/**
		 * This object contains the stage coordinates of the mouse for the current frame.
		 */
		private const _lastMousePoint:Point = new Point(NaN, NaN);
		
		/**
		 * This is the stage location of the last mouse-down event.
		 */
		private const _lastMouseDownPoint:Point = new Point(NaN, NaN);
		
		/**
		 * This is a special pseudo-event supported by StageUtils.
		 * Callbacks added to this event will only trigger when the mouse was clicked and released at the same screen location.
		 */
		public static const POINT_CLICK_EVENT:String = "pointClick";
	}
}
