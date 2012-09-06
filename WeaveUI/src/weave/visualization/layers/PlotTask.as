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

package weave.visualization.layers
{
	import flash.display.Bitmap;
	import flash.display.BitmapData;
	
	import weave.api.WeaveAPI;
	import weave.api.core.IDisposableObject;
	import weave.api.core.ILinkableObject;
	import weave.api.data.IKeyFilter;
	import weave.api.data.IQualifiedKey;
	import weave.api.detectLinkableObjectChange;
	import weave.api.disposeObjects;
	import weave.api.getCallbackCollection;
	import weave.api.linkBindableProperty;
	import weave.api.linkableObjectIsBusy;
	import weave.api.newDisposableChild;
	import weave.api.primitives.IBounds2D;
	import weave.api.registerLinkableChild;
	import weave.api.ui.IPlotTask;
	import weave.api.ui.IPlotter;
	import weave.core.CallbackCollection;
	import weave.data.AttributeColumns.StreamedGeometryColumn;
	import weave.primitives.Bounds2D;
	import weave.primitives.ZoomBounds;
	import weave.utils.PlotterUtils;
	import weave.utils.SpatialIndex;

	/**
	 * Callbacks are triggered when the rendering task completes, or the plotter becomes busy during rendering.
	 * Busy status should be checked when callbacks trigger.
	 * 
	 * @author adufilie
	 */
	public class PlotTask implements IPlotTask, ILinkableObject, IDisposableObject
	{
		public static var debugMouseDownPause:Boolean = false;
		
		private static const $debugTrace:Function = debugTrace;
		
		private function debugTrace(...args):void
		{
			return; // comment this out to enable debugging
			
			args.unshift(toString());
			$debugTrace.apply(null, args);
		}
		
		public function toString():String
		{
			var str:String = [
				debugId(_plotter),
				debugId(this),
				['subset','selection','probe'][_taskType]
			].join('-');
			
			if (linkableObjectIsBusy(this))
				str += '(busy)';
			
			return str;
		}
		
		public static const TASK_TYPE_SUBSET:int = 0;
		public static const	TASK_TYPE_SELECTION:int = 1;
		public static const TASK_TYPE_PROBE:int = 2;
		
		/**
		 * @param plotter
		 * @param taskType One of TASK_TYPE_SUBSET, TASK_TYPE_SELECTION, TASK_TYPE_PROBE
		 * @param spatialIndex
		 * @param zoomBounds
		 * @param layerSettings
		 */		
		public function PlotTask(taskType:int, plotter:IPlotter, spatialIndex:SpatialIndex, zoomBounds:ZoomBounds, layerSettings:LayerSettings)
		{
			// _dependencies is used as the parent so we can check its busy status with a single function call.
			_taskType = taskType;
			_plotter = plotter;
			_spatialIndex = spatialIndex;
			_zoomBounds = zoomBounds;
			_layerSettings = layerSettings;
			
			var keyFilters:Array = [_layerSettings.subsetFilter, _layerSettings.selectionFilter, _layerSettings.probeFilter];
			var keyFilter:ILinkableObject = keyFilters[_taskType];
			var list:Array = [_plotter, _spatialIndex, _zoomBounds, _layerSettings, keyFilter];
			for each (var dependency:ILinkableObject in list)
				registerLinkableChild(_dependencies, dependency);
			
			_dependencies.addImmediateCallback(this, asyncStart, true);
			
			linkBindableProperty(_layerSettings.visible, completedBitmap, 'visible');
		}
		
		public function dispose():void
		{
			_plotter = null;
			_spatialIndex = null;
			_zoomBounds = null;
			_layerSettings = null;
			disposeObjects(completedBitmap.bitmapData, _buffer.bitmapData);
		}
		
		public function get taskType():int { return _taskType; }
		
		/**
		 * This Bitmap contains the BitmapData that was last generated completely by the plotter.
		 */		
		public const completedBitmap:Bitmap = new Bitmap(null, 'auto', true);
		/**
		 * This is the dataBounds that was used to generate the completedBitmap.
		 */
		public const completedDataBounds:IBounds2D = new Bounds2D();
		/**
		 * This is the screenBounds corresponding to the dataBounds that was used to generate the completedBitmap.
		 */
		public const completedScreenBounds:IBounds2D = new Bounds2D();
		
		private var _dependencies:CallbackCollection = newDisposableChild(this, CallbackCollection);
		private var _prevBusyGroupTriggerCounter:uint = 0;
		
		private var _unscaledWidth:int = 0;
		private var _unscaledHeight:int = 0;
		
		private var _taskType:int = -1;
		private var _plotter:IPlotter = null;
		private var _spatialIndex:SpatialIndex;
		private var _zoomBounds:ZoomBounds;
		private var _layerSettings:LayerSettings;
		
		private var _buffer:Bitmap = new Bitmap();
		private var _dataBounds:Bounds2D = new Bounds2D();
		private var _screenBounds:Bounds2D = new Bounds2D();
		private var _iteration:uint = 0;
		private var _keyFilter:IKeyFilter;
		private var _recordKeys:Array;
		private var _asyncState:Object = {};
		private var _pendingKeys:Array;
		private var _iPendingKey:uint;
		
		/**
		 * This function must be called to set the size of the BitmapData buffer.
		 * @param width New width of the buffer, in pixels
		 * @param height New height of the buffer, in pixels
		 */
		public function setBitmapDataSize(width:int, height:int):void
		{
			if (_unscaledWidth != width || _unscaledHeight != height)
			{
				_unscaledWidth = width;
				_unscaledHeight = height;
				_dependencies.triggerCallbacks();
			}
		}
		
		/**
		 * This returns true if the layer should be rendered and selectable/probeable
		 * @return true if the layer should be rendered and selectable/probeable
		 */
		private function shouldBeRendered():Boolean
		{
			var visible:Boolean = true;
			if (!_layerSettings.visible.value)
			{
				debugTrace('visible=false');
				visible = false;
			}
			else if (!_layerSettings.selectable.value && _taskType != TASK_TYPE_SUBSET)
			{
				debugTrace('selection disabled');
				visible = false;
			}
			else
			{
				// HACK - begin validating spatial index if necessary, because this may affect zoomBounds
				if (detectLinkableObjectChange(_spatialIndex.createIndex, _plotter.spatialCallbacks))
					_spatialIndex.createIndex(_plotter, _layerSettings.hack_includeMissingRecordBounds);
				
				var min:Number = _layerSettings.minVisibleScale.value;
				var max:Number = _layerSettings.maxVisibleScale.value;
				var xScale:Number = _zoomBounds.getXScale();
				var yScale:Number = _zoomBounds.getYScale();
				visible = min <= xScale && xScale <= max
					&& min <= yScale && yScale <= max;
			}
			
			if (!visible)
			{
				WeaveAPI.SessionManager.unassignBusyTask(_dependencies);
				
				disposeObjects(_buffer.bitmapData);
				_buffer.bitmapData = null;
				disposeObjects(completedBitmap.bitmapData);
				completedBitmap.bitmapData = null;
				completedDataBounds.reset();
				completedScreenBounds.reset();
			}
			return visible;
		}
		
		private function asyncStart(..._):void
		{
			if (shouldBeRendered())
			{
				debugTrace('begin async rendering');
				WeaveAPI.StageUtils.startTask(this, asyncIterate, WeaveAPI.TASK_PRIORITY_RENDERING, asyncComplete);
				
				// assign secondary busy task in case async task gets cancelled due to busy dependencies
				WeaveAPI.SessionManager.assignBusyTask(_dependencies, this);
			}
			else
			{
				debugTrace('should not be rendered');
			}
		}
		
		private function asyncIterate():Number
		{
			if (debugMouseDownPause && WeaveAPI.StageUtils.mouseButtonDown)
				return 0;
			
			// if plotter is busy, stop immediately
			if (WeaveAPI.SessionManager.linkableObjectIsBusy(_dependencies))
			{
				debugTrace('dependencies are busy');
				return 1;
			}
			
			/***** initialize *****/

			// restart if necessary, initializing variables
			if (_prevBusyGroupTriggerCounter != _dependencies.triggerCounter)
			{
				_prevBusyGroupTriggerCounter = _dependencies.triggerCounter;
				
				_iteration = 0;
				_iPendingKey = 0;
				_pendingKeys = _plotter.keySet.keys;
				_recordKeys = [];
				_zoomBounds.getDataBounds(_dataBounds);
				_zoomBounds.getScreenBounds(_screenBounds);
				if (_taskType == TASK_TYPE_SUBSET)
					_keyFilter = _layerSettings.subsetFilter.getInternalKeyFilter();
				else if (_taskType == TASK_TYPE_SELECTION)
					_keyFilter = _layerSettings.selectionFilter.getInternalKeyFilter();
				else if (_taskType == TASK_TYPE_PROBE)
					_keyFilter = _layerSettings.probeFilter.getInternalKeyFilter();

				// stop immediately if we shouldn't be rendering
				if (!shouldBeRendered())
					return 1;
				
				// clear bitmap and resize if necessary
				PlotterUtils.setBitmapDataSize(_buffer, _unscaledWidth, _unscaledHeight);

				// stop immediately if the bitmap is invalid
				if (PlotterUtils.bitmapDataIsEmpty(_buffer))
				{
					debugTrace('bitmap is empty');
					return 1;
				}
				
				// hacks
				hack_requestGeometryDetail();
				
				// hack - draw background on subset layer
				if (_taskType == TASK_TYPE_SUBSET)
					_plotter.drawBackground(_dataBounds, _screenBounds, _buffer.bitmapData);
			}
			
			/***** prepare keys *****/
			
			// if keys aren't ready yet, prepare keys
			if (_pendingKeys)
			{
				if (_iPendingKey < _pendingKeys.length)
				{
					// next key iteration - add key if included in filter and on screen
					var key:IQualifiedKey = _pendingKeys[_iPendingKey] as IQualifiedKey;
					if (!_keyFilter || _keyFilter.containsKey(key)) // accept all keys if _keyFilter is null
					{
						for each (var keyBounds:IBounds2D in _spatialIndex.getBoundsFromKey(key))
						{
							if (keyBounds.overlaps(_dataBounds))
							{
								if (!keyBounds.isUndefined() || _layerSettings.hack_includeMissingRecordBounds)
									_recordKeys.push(key);
								break;
							}
						}
					}
					
					// prepare for next iteration
					_iPendingKey++;
					
					// not done yet
					return 0;
				}
				// done with keys
				_pendingKeys = null;
			}
			
			/***** draw *****/
			
			// next draw iteration
			var progress:Number = _plotter.drawPlotAsyncIteration(this);
			
			// prepare for next iteration
			_iteration++;
			
			return progress;
		}
		
		private function asyncComplete():void
		{
			debugTrace('rendering completed');
			// if visible is false or the plotter is busy, the graphics aren't ready, so don't trigger callbacks
			if (shouldBeRendered() && !WeaveAPI.SessionManager.linkableObjectIsBusy(_dependencies))
			{
				// busy task gets unassigned when the render completed successfully
				WeaveAPI.SessionManager.unassignBusyTask(_dependencies);

				// BitmapData has been completely rendered, so update completedBitmap and completedDataBounds
				var oldBitmapData:BitmapData = completedBitmap.bitmapData;
				completedBitmap.bitmapData = _buffer.bitmapData;
				_buffer.bitmapData = oldBitmapData;
				completedDataBounds.copyFrom(_dataBounds);
				completedScreenBounds.copyFrom(_screenBounds);
				
				getCallbackCollection(this).triggerCallbacks();
			}
		}
		
		
		/*************
		 **  hacks  **
		 *************/
		
		private function hack_requestGeometryDetail():void
		{
			var minImportance:Number = _dataBounds.getArea() / _screenBounds.getArea();
			
			// find nested StreamedGeometryColumn objects
			var descendants:Array = WeaveAPI.SessionManager.getLinkableDescendants(_dependencies, StreamedGeometryColumn);
			// request the required detail
			for each (var streamedColumn:StreamedGeometryColumn in descendants)
			{
				var requestedDataBounds:IBounds2D = _dataBounds;
				var requestedMinImportance:Number = minImportance;
				if (requestedDataBounds.isUndefined())// if data bounds is empty
				{
					// use the collective bounds from the geometry column and re-calculate the min importance
					requestedDataBounds = streamedColumn.collectiveBounds;
					requestedMinImportance = requestedDataBounds.getArea() / _screenBounds.getArea();
				}
				// only request more detail if requestedDataBounds is defined
				if (!requestedDataBounds.isUndefined())
					streamedColumn.requestGeometryDetail(requestedDataBounds, requestedMinImportance);
			}
		}
		
		
		/***************************
		 **  IPlotTask interface  **
		 ***************************/
		
		/**
		 * This is the off-screen buffer, which may change
		 */
		public function get buffer():BitmapData
		{
			return _buffer.bitmapData;
		}
		
		/**
		 * This specifies the range of data to be rendered
		 */
		public function get dataBounds():IBounds2D
		{
			return _dataBounds;
		}
		
		/**
		 * This specifies the pixel range where the graphics should be rendered
		 */
		public function get screenBounds():IBounds2D
		{
			return _layerSettings.hack_lockScreenBounds || _screenBounds;
		}
		
		/**
		 * These are the IQualifiedKey objects identifying which records should be rendered
		 */
		public function get recordKeys():Array
		{
			return _recordKeys;
		}
		
		/**
		 * This counter is incremented after each iteration.  When the task parameters change, this counter is reset to zero.
		 */
		public function get iteration():uint
		{
			return _iteration;
		}
		
		/**
		 * This object can be used to optionally store additional state variables for resuming an asynchronous task where it previously left off.
		 * Setting this will not reset the iteration counter.
		 */
		public function get asyncState():Object
		{
			return _asyncState;
		}
		public function set asyncState(value:Object):void
		{
			_asyncState = value;
		}
	}
}
