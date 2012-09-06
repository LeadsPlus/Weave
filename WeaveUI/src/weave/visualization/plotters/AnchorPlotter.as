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

package weave.visualization.plotters
{	
	import flash.display.BitmapData;
	import flash.display.Graphics;
	import flash.geom.Matrix;
	import flash.geom.Point;
	import flash.geom.Rectangle;
	import flash.utils.Dictionary;
	
	import weave.api.WeaveAPI;
	import weave.api.data.IQualifiedKey;
	import weave.api.primitives.IBounds2D;
	import weave.api.registerLinkableChild;
	import weave.api.ui.IPlotTask;
	import weave.api.ui.ITextPlotter;
	import weave.core.LinkableBoolean;
	import weave.core.LinkableHashMap;
	import weave.core.LinkableNumber;
	import weave.data.KeySets.KeySet;
	import weave.primitives.Bounds2D;
	import weave.primitives.ColorRamp;
	import weave.utils.BitmapText;
	import weave.utils.LinkableTextFormat;

	/**
	 * AnchorPlotter
	 * @author kmanohar
	 */	
	public class AnchorPlotter extends AbstractPlotter implements ITextPlotter
	{
		public var anchors:LinkableHashMap = newSpatialProperty(LinkableHashMap,handleAnchorsChange);
		public const labelAngleRatio:LinkableNumber = registerSpatialProperty(new LinkableNumber(0, verifyLabelAngleRatio));
		
		private var _keySet:KeySet;
		private const tempPoint:Point = new Point();
		private const _bitmapText:BitmapText = new BitmapText();
		public const enableWedgeColoring:LinkableBoolean = registerLinkableChild(this, new LinkableBoolean(false), fillColorMap);
		public const colorMap:ColorRamp = registerLinkableChild(this, new ColorRamp(ColorRamp.getColorRampXMLByName("Doppler Radar")),fillColorMap);
		public var anchorColorMap:Dictionary;
		
		//Fill this hash map with bounds of every record key for efficient look up in getDataBoundsFromRecordKey
		private var keyBoundsMap:Dictionary = new Dictionary();
		private const _currentScreenBounds:Bounds2D = new Bounds2D();
		private const _currentDataBounds:Bounds2D = new Bounds2D();
		
		public function AnchorPlotter()	
		{
			registerLinkableChild(this, LinkableTextFormat.defaultTextFormat); // redraw when text format changes
		}
		
		public function handleAnchorsChange():void
		{		
			var keys:Array = anchors.getNames(AnchorPoint);
			var keyArray:Array = WeaveAPI.QKeyManager.getQKeys('dimensionAnchors',keys);

			_keySet = new KeySet();
			_keySet.replaceKeys(keyArray);
			setKeySource(_keySet);				
			fillColorMap();
		}			
		
		private function fillColorMap():void
		{
			var i:int = 0;
			anchorColorMap = new Dictionary(true);
			var _anchors:Array = anchors.getObjects(AnchorPoint);
			
			for each( var anchor:AnchorPoint in anchors.getObjects())
			{
				anchorColorMap[anchors.getName(anchor)] = colorMap.getColorFromNorm(i / (_anchors.length - 1)); 
				i++;
			}
		}
		
		override public function drawPlotAsyncIteration(task:IPlotTask):Number
		{
			drawAll(task.recordKeys, task.dataBounds, task.screenBounds, task.buffer);
			return 1;
		}
		private function drawAll(recordKeys:Array, dataBounds:IBounds2D, screenBounds:IBounds2D, destination:BitmapData):void
		{
			var array:Array = anchors.getObjects(AnchorPoint);
			var x:Number; 
			var y:Number;
			
			var anchor:AnchorPoint;
			var radians:Number;
			keyBoundsMap = new Dictionary();

			var graphics:Graphics = tempShape.graphics;
			graphics.clear();
						
			graphics.lineStyle(1);
			// loop through anchors hash map and draw dimensional anchors and labels	
			for each(var key:IQualifiedKey in recordKeys)
			{
				anchor = anchors.getObject(key.localName) as AnchorPoint;
				
				x = anchor.x.value;
				y = anchor.y.value;
				radians = anchor.polarRadians.value;
				var radius:Number = anchor.radius.value;
				
				var cos:Number = Math.cos(radians);
				var sin:Number = Math.sin(radians);
				
				tempPoint.x = radius * cos;
				tempPoint.y = radius * sin;
				dataBounds.projectPointTo(tempPoint, screenBounds);

				// draw circle
				if(enableWedgeColoring.value)
					graphics.beginFill(anchorColorMap[key.localName]);				
				graphics.drawCircle(tempPoint.x, tempPoint.y, 5);				
				graphics.endFill();
				
				_bitmapText.trim = false;
				_bitmapText.text = " " + anchor.title.value + " ";
				
				_bitmapText.verticalAlign = BitmapText.VERTICAL_ALIGN_MIDDLE;
				
				_bitmapText.angle = screenBounds.getYDirection() * (radians * 180 / Math.PI);
				_bitmapText.angle = (_bitmapText.angle % 360 + 360) % 360;
				if (cos > -0.000001) // the label exactly at the bottom will have left align
				{
					_bitmapText.horizontalAlign = BitmapText.HORIZONTAL_ALIGN_LEFT;
					// first get values between -90 and 90, then multiply by the ratio
					_bitmapText.angle = ((_bitmapText.angle + 90) % 360 - 90) * labelAngleRatio.value;
				}
				else
				{
					_bitmapText.horizontalAlign = BitmapText.HORIZONTAL_ALIGN_RIGHT;
					// first get values between -90 and 90, then multiply by the ratio
					_bitmapText.angle = (_bitmapText.angle - 180) * labelAngleRatio.value;
				}
				
				LinkableTextFormat.defaultTextFormat.copyTo(_bitmapText.textFormat);				
				_bitmapText.x = tempPoint.x;
				_bitmapText.y = tempPoint.y;
				
				// draw almost-invisible rectangle behind text
				/*_bitmapText.getUnrotatedBounds(_tempBounds);
				_tempBounds.getRectangle(_tempRectangle);				
				destination.fillRect(_tempRectangle, 0x02808080);*/
				
				// draw bitmap text
				_bitmapText.draw(destination);								
			}
			destination.draw(tempShape);							
			
			_currentScreenBounds.copyFrom(screenBounds);
			_currentDataBounds.copyFrom(dataBounds);
		}
		
		override public function drawBackground(dataBounds:IBounds2D, screenBounds:IBounds2D, destination:BitmapData):void
		{
			super.drawBackground(dataBounds,screenBounds,destination);
			
			_currentScreenBounds.copyFrom(screenBounds);
			_currentDataBounds.copyFrom(dataBounds);
		}
		
		override public function getDataBoundsFromRecordKey(recordKey:IQualifiedKey):Array
		{
			if( !anchors ) return null;
			
			var anchor:AnchorPoint = anchors.getObject(recordKey.localName) as AnchorPoint;
			var bounds:IBounds2D = getReusableBounds();			
			
			tempPoint.x = anchor.x.value;
			tempPoint.y = anchor.y.value;
			
			bounds.includePoint(tempPoint);				
			
			return [bounds];			
		}
		
		override public function getBackgroundDataBounds():IBounds2D
		{
			return getReusableBounds(-1, -1.1, 1, 1.1);
		}
		
		private function verifyLabelAngleRatio(value:Number):Boolean
		{
			return 0 <= value && value <= 1;
		}
		
		private var _matrix:Matrix = new Matrix();
		private const _tempBounds:Bounds2D = new Bounds2D();
		private var _tempRectangle:Rectangle = new Rectangle();
		
		private function drawRectangle(graphics:Graphics,destination:BitmapData):void
		{
			_bitmapText.getUnrotatedBounds(_tempBounds);			
			_tempBounds.getRectangle(_tempRectangle);
			
			//graphics.drawRect(_tempRectangle.x, _tempRectangle.y, _tempRectangle.width, _tempRectangle.height);
			
			destination.fillRect(_tempRectangle,  0x02808080);
			return;
			var height:Number = _tempBounds.getWidth();
			var width:Number = _tempBounds.getHeight();
			
			/*_tempBounds.getRectangle(_tempRectangle);
			var p1:Point = new Point();
			_tempBounds.getMinPoint(p1);
			var p2:Point = new Point(_tempBounds.xMin, _tempBounds.yMax);
			var p3:Point = new Point();
			_tempBounds.getMaxPoint(p3);
			var p4:Point = new Point(_tempBounds.xMax, _tempBounds.yMin);
			var angle:Number = _bitmapText.angle;
			angle = angle * Math.PI/180;
			var p:Point = new Point();
			_tempBounds.getMinPoint(p);
						
			graphics.moveTo(p1.x,p1.y);
			graphics.lineTo(p2.x,p2.y);
			graphics.moveTo(p2.x,p2.y);
			graphics.lineTo(p3.x,p3.y);
			graphics.moveTo(p3.x,p3.y);
			graphics.lineTo(p4.x,p4.y);
			graphics.moveTo(p4.x,p4.y);
			graphics.lineTo(p1.x,p1.y);*/
			//graphics.drawRect(rect.x, rect.y, rect.width, rect.height);
		}		
		public function rotatePoint(p:Point, o:Point, d:Number):Point{
			
			var np:Point = new Point();
			p.x += (0 - o.x);
			p.y += (0 - o.y);
			np.x = (p.x * Math.cos(d)) - (p.y * Math.sin(d));
			np.y = Math.sin(d) * p.x + Math.cos(d) * p.y;
			np.x += (0 + o.x);
			np.y += (0 + o.y)
			
			return np;
			
		}
	}	
}