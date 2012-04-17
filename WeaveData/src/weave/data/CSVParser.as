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

package weave.data
{
	import mx.utils.StringUtil;
	
	import weave.api.data.ICSVParser;

	/**
	 * This is an all-static class containing functions to parse and generate valid CSV files.
	 * Ported from AutoIt Script to Flex. Original author: adufilie
	 * 
	 * @author skolman
	 * @author adufilie
	 */	
	public class CSVParser implements ICSVParser
	{
		public function CSVParser(delimiter:String = ',', quote:String = '"')
		{
			if (delimiter && delimiter.length == 1)
				this.delimiter = delimiter;
			if (quote && quote.length == 1)
				this.quote = quote;
		}
		
		private var delimiter:String = ',';
		private var quote:String = '"';
		private static const CR:String = '\r';
		private static const LF:String = '\n';
		private static const CRLF:String = '\r\n';
		
		/**
		 * This will parse a CSV String into a two-dimensional Array of String values.
		 * @param csvData The CSV String to parse.
		 * @param parseTokens If this is true, tokens surrounded in quotes will be unquoted and escaped characters will be unescaped.
		 * @return The destination Array, or a new Array if none was specified.  The result of parsing the CSV string will be stored here.
		 */
		public function parseCSV(csvData:String, parseTokens:Boolean = true, destination:Array = null):Array
		{
			var csvDataArray:Array = destination ? destination : [];
			csvDataArray.length = 0; // clear any existing data in the output Array
			
			// special case -- if csvData is null or empty string, return an empty array (a set of zero rows)
			if (csvData == null || csvData == '')
				return csvDataArray;
			
			var row:int= 0;
			var col:int= 0;
			
			csvDataArray[row] = [''];
			var escaped:Boolean = false;
			
			var fileSize:int = csvData ? csvData.length : 0; // handle null parameter
			
			for (var i:int = 0; i < fileSize; i++)
			{
				var currentChar:String = csvData.charAt(i);
				var twoChar:String = currentChar + csvData.charAt(i+1);
				if (escaped)
				{
					if (twoChar == quote+quote) //escaped quote
					{
						csvDataArray[row][col] += (parseTokens?currentChar:twoChar);//append quote(s) to current token
						i +=1; //skip second quote mark
					}
					else if (currentChar == quote)	//end of escaped text
					{
						escaped = false;
						if (!parseTokens)
						{
							csvDataArray[row][col] += currentChar;//append quote to current token
						}
					}
					else
					{
						csvDataArray[row][col] += currentChar;//append quotes to current token
					}
				}
				else
				{
					
					if (twoChar == delimiter+quote)
					{
						escaped = true;
						col += 1;
						csvDataArray[row][col] = (parseTokens?'':quote);
						i += 1; //skip quote mark
					}
					else if (currentChar == quote && csvDataArray[row][col] == '')		//start new token
					{
						escaped = true;
						if (!parseTokens) 
							csvDataArray[row][col] += currentChar;
					}
					else if (currentChar == delimiter)		//start new token
					{
						col += 1;
						csvDataArray[row][col] = '';
					}
					else if (twoChar == CRLF)	//then start new row
					{
						i +=1; //skip line feed
						row += 1;
						col = 0;
						csvDataArray[row] = [''];
					}
					else if (currentChar == CR)	//then start new row
					{
						row += 1;
						col = 0;
						csvDataArray[row] = [''];
					}
					else if (currentChar == LF)	//then start new row
					{ 
						row += 1;
						col = 0;
						csvDataArray[row] = [''];
					}
					else //append single character to current token
						csvDataArray[row][col] += currentChar;	
				}			
			}
			
			// if there is more than one row and last row is empty,
			// remove last row assuming it is there because of a newline at the end of the file.
			for (var iRow:int = csvDataArray.length - 1; iRow >= 0; --iRow)
			{
				var dataLine:Array = csvDataArray[iRow];
				
				if (dataLine.length == 1 && dataLine[0] == '')
					csvDataArray.splice(iRow, 1);
			}
			
			return csvDataArray;
		}
		
		/**
		 * This will generate a CSV String from an Array of rows in a table.
		 * @param rows A two-dimensional Array, which will be accessed like rows[rowIndex][columnIndex].
		 * @return A CSV String containing the values from the rows.
		 */
		public function createCSV(rows:Array):String
		{
			var lines:Array = [];
			for (var i:int = 0; i < rows.length; i++)
			{
				var tokens:Array = [];
				for (var j:int = 0; j < rows[i].length; j++)
					tokens[j] = createCSVToken(rows[i][j]);
				
				lines[i] = tokens.join(delimiter);
			}
			var csvData:String = lines.join(LF);
			return csvData;
		}
		
		/**
		 * This will parse a CSV-encoded String value.
		 * If string begins with ", text up until the matching " will be parsed, replacing "" with ".
		 * @param token A CSV-encoded String value.
		 * @return The decoded String value.
		 */
		public function parseCSVToken(token:String):String
		{
			var parsedToken:String = '';
			
			var tokenLength:int = token.length;
			
			if (token.charAt(0) == quote)
			{
				var escaped:Boolean = true;
				for (var i:int = 1; i <= tokenLength; i++)
				{
					var currentChar:String = token.charAt(i);
					var twoChar:String = currentChar + token.charAt(i+1);
					
					if (twoChar == quote+quote) //append escaped quote
					{
						i += 1;
						parsedToken += quote;
					}
					else if (currentChar == quote && escaped)
					{
						escaped = false;
					}
					else
					{
						parsedToken += currentChar;
					}
				}
			}
			else
			{
				parsedToken = token;
			}
			return parsedToken;
		}
		
		/**
		 * This will surround a string with quotes and use CSV-style escape sequences if necessary.
		 * @param str A String value.
		 * @return The String value using CSV encoding.
		 */
		public function createCSVToken(str:String):String
		{
			if (str == null)
				str = '';
			
			// determine if quotes are necessary
			if ( str.length > 0
				&& str.indexOf(quote) < 0
				&& str.indexOf(delimiter) < 0
				&& str.indexOf(LF) < 0
				&& str.indexOf(CR) < 0
				&& str == StringUtil.trim(str) )
			{
				return str;
			}

			var token:String = quote;
			for (var i:int = 0; i <= str.length; i++)
			{
				var currentChar:String = str.charAt(i);
				if (currentChar == quote)
					token += quote + quote;
				else
					token += currentChar; 
			}
			return token + quote;
		}
		
		/**
		 * This function converts an Array of Arrays to an Array of Objects compatible with DataGrid.
		 * @param rows An Array of Arrays, the first being a header line containing property names
		 * @return An Array of Objects containing String properties using the names in the header line.
		 */
		public function convertRowsToRecords(rows:Array):Array
		{
			var i:int;
			var j:int;
			var records:Array = [];
			var header:Array = rows[0];
			
			for (i = 1; i < rows.length; i++)
			{
				var record:Object = {};
				for (j = 0; j < header.length; j++)
					record[header[j]] = rows[i][j];	
				records.push(record);
			}
			return records;
		}
		
		/**
		 * This function returns a comprehensive list of all the field names defined by a list of record objects.
		 * @param records An Array of record objects.
		 * @param includeNullFields If this is true, fields that have null values will be included.
		 * @return A comprehensive list of all the field names defined by the given record objects.
		 */
		public function getRecordFieldNames(records:Array, includeNullFields:Boolean = false):Array
		{
			var hashmap:Object = {};
			var field:String;
			for each (var record:Object in records)
				for (field in record)
					if (includeNullFields || record[field] != null)
						hashmap[field] = true;
			var fields:Array = [];
			for (field in hashmap)
				fields.push(field);
			return fields;
		}
		
		/**
		 * This function converts an Array of Objects (compatible with DataGrid) to an Array of Arrays
		 * compatible with other functions in this class.
		 * @param records An Array of Objects containing String properties.
		 * @param columnOrder An optional list of column names to use in order.
		 * @param allowBlankColumns If this is set to true, then the function will include all columns even if they are blank.
		 * @return An Array of Arrays, the first being a header line containing all the property names.
		 */
		public function convertRecordsToRows(records:Array, columnOrder:Array = null, allowBlankColumns:Boolean = false):Array
		{
			var i:int;
			var j:int;
			var header:Array = columnOrder;
			var rows:Array = [];
			
			if (header == null)
				header = getRecordFieldNames(records, allowBlankColumns).sort();
			
			rows.push(header);
			
			for (i = 0; i < records.length; i++)
			{
				var row:Array = [];
				for (j = 0; j < header.length; j++)
					row.push(records[i][header[j]]);
				rows.push(row);
			}
			return rows;
		}
	}
}
