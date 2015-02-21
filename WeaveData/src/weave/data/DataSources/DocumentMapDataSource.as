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

package weave.data.DataSources
{
	import avmplus.getQualifiedClassName;
	
	import mx.rpc.AsyncToken;
	import mx.rpc.events.FaultEvent;
	import mx.rpc.events.ResultEvent;
	import mx.utils.ObjectUtil;
	
	import weave.api.core.ICallbackCollection;
	import weave.api.data.ColumnMetadata;
	import weave.api.data.DataType;
	import weave.api.data.IAttributeColumn;
	import weave.api.data.IDataSource;
	import weave.api.data.IDataSource_Service;
	import weave.api.data.IQualifiedKey;
	import weave.api.data.IWeaveTreeNode;
	import weave.api.detectLinkableObjectChange;
	import weave.api.disposeObject;
	import weave.api.getCallbackCollection;
	import weave.api.newLinkableChild;
	import weave.api.objectWasDisposed;
	import weave.api.registerDisposableChild;
	import weave.api.registerLinkableChild;
	import weave.api.reportError;
	import weave.compiler.Compiler;
	import weave.core.CallbackCollection;
	import weave.core.LinkableString;
	import weave.data.AttributeColumns.DateColumn;
	import weave.data.AttributeColumns.EquationColumn;
	import weave.data.AttributeColumns.NumberColumn;
	import weave.data.AttributeColumns.ProxyColumn;
	import weave.data.AttributeColumns.StringColumn;
	import weave.data.QKeyManager;
	import weave.data.hierarchy.ColumnTreeNode;
	import weave.services.AMF3Servlet;
	import weave.services.ProxyAsyncToken;
	import weave.services.addAsyncResponder;
	import weave.utils.VectorUtils;
	
	public class DocumentMapDataSource extends AbstractDataSource implements IDataSource_Service
	{
		WeaveAPI.ClassRegistry.registerImplementation(IDataSource, DocumentMapDataSource, "Document Map server");
		
		public function DocumentMapDataSource()
		{
			url.addImmediateCallback(this, handleURLChange, true);
			rServiceUrl.addImmediateCallback(this, handleRURLChange, true);
		}
		
		private static const DEFAULT_BASE_URL:String = '/WeaveServices';
		private static const DEFAULT_SERVLET_NAME:String = '/DocumentMapService';
		
		public static const META_COLLECTION:String = 'DocumentMapDataSource_collection';
		public static const META_TABLE:String = 'DocumentMapDataSource_table';
		public static const META_COLUMN:String = 'DocumentMapDataSource_column';
		
		public static const META_ID_FIELDS:Array = [META_COLLECTION, META_TABLE, META_COLUMN];
		
		public static const TABLE_TOPICS:String = 'topics';
		public static const TABLE_DOC_METADATA:String = 'document_metadata';
		public static const TABLE_DOC_FILES:String = 'document_files';
		public static const TABLE_DOC_WEIGHTS:String = 'document_weights';
		public static const TABLE_NODES:String = 'nodes';
		
		public static const COLUMN_DOC_TITLE:String = 'title';
		public static const COLUMN_DOC_MODIFIED_TIME:String = 'modifiedTime';
		public static const COLUMN_DOC_URL:String = 'url';
		public static const COLUMN_DOC_THUMBNAIL:String = 'thumbnail';
		public static const COLUMN_TOPIC:String = 'topic';
		public static const COLUMN_NODE_TYPE:String = 'type';
		public static const COLUMN_NODE_X:String = 'x';
		public static const COLUMN_NODE_Y:String = 'y';
		
		private var _service:AMF3Servlet = null;
		private var _rService:AMF3Servlet = null;
		public const url:LinkableString = registerLinkableChild(this, new LinkableString('/DocumentMapService/'));
		public const rServiceUrl:LinkableString = registerLinkableChild(this, new LinkableString('http://corsac.binaryden.net:8080/WeaveServices/RService'));
		
		private function handleURLChange():void
		{
			disposeObject(_service);
			_service = registerLinkableChild(this, new AMF3Servlet(url.value));
			_listCollectionsCallbacks.triggerCallbacks();
		}
		
		private function handleRURLChange():void
		{
			disposeObject(_rService);
			_rService = registerLinkableChild(this, new AMF3Servlet(rServiceUrl.value));
		}
		
		/**
		 * This gets called as a grouped callback when the session state changes.
		 */
		override protected function initialize():void
		{
			super.initialize();
			
			if (detectLinkableObjectChange(initialize, url, rServiceUrl))
			{
				
			}
		}
		
		/**
		 * Classes that extend AbstractDataSource can define their own replacement for this function.
		 * All column requests will be delayed as long as this accessor function returns false.
		 * The default behavior is to return false during the time between a change in the session state and when initialize() is called.
		 */		
		override protected function get initializationComplete():Boolean
		{
			return _initializeCalled;
		}

		
		override public function refreshHierarchy():void
		{
			super.refreshHierarchy();
			_cache = {};
		}
		
		private var _cache:Object = {};
		/**
		 * @param resultCastFunction A function like function(result:Object):Object which converts the raw servlet result to another format.
		 */
		private function rpc(methodName:String, methodParameters:Array = null, resultCastFunction:Function = null):*
		{
			var stringified:String = Compiler.stringify({method: methodName, params: methodParameters});
			if (!_cache.hasOwnProperty(stringified))
			{
				_cache[stringified] = null;
				var proxyAsyncToken:ProxyAsyncToken = new ProxyAsyncToken(_service.invokeAsyncMethod, [methodName, methodParameters], resultCastFunction, false);
				addAsyncResponder(proxyAsyncToken, handleRPC, handleFault, {service: _service, stringified: stringified});
				proxyAsyncToken.invoke();
			}
			return _cache[stringified];
		}
		private function handleRPC(event:ResultEvent, token:Object):void
		{
			if (token.service != _service)
				return;
			
			_cache[token.stringified] = event.result;
			getCallbackCollection(this).triggerCallbacks();
		}
		
		public function getKeyType(collection:String):String { return WeaveAPI.globalHashMap.getName(this) + '_' + collection; }
		
		private function getColumnNodeDescriptors(collection:String, table:String, columnNames:Array):Array
		{
			return columnNames.map(function(column:String, i:int, a:Array):Object {
				return {
					//label: function():String { return getColumnMetadata(collection, table, column)[ColumnMetadata.TITLE]; },
					source: this,
					idFields: META_ID_FIELDS,
					columnMetadata: getColumnMetadata(collection, table, column)
				};
			}, this);
		}
		
		private function getColumnMetadata(collection:String, table:String, column:String):Object
		{
			var dataType:String = DataType.STRING;
			if (table == TABLE_DOC_METADATA && column == COLUMN_DOC_MODIFIED_TIME)
				dataType = DataType.DATE;
			if (table == TABLE_DOC_WEIGHTS)
				dataType = DataType.NUMBER;
			else if (table == TABLE_NODES && column != COLUMN_NODE_TYPE)
				dataType = DataType.NUMBER;
			
			var title:String = column;
			if (table == TABLE_DOC_WEIGHTS)
			{
				var topicWordsColumn:IAttributeColumn = getCachedColumn(collection, TABLE_TOPICS, COLUMN_TOPIC);
				if (topicWordsColumn)
				{
					var keyType:String = getKeyType(collection);
					title = topicWordsColumn.getValueFromKey(WeaveAPI.QKeyManager.getQKey(keyType, column), String) || title;
				}
			}
			
			var meta:Object = {};
			meta[ColumnMetadata.TITLE] = title;
			meta[ColumnMetadata.KEY_TYPE] = getKeyType(collection);
			meta[ColumnMetadata.DATA_TYPE] = dataType;
			meta[META_COLLECTION] = collection;
			meta[META_TABLE] = table;
			meta[META_COLUMN] = column;
			return meta;
		}
		
		private function getCachedColumn(collection:String, table:String, column:String):IAttributeColumn
		{
			var stringified:String = Compiler.stringify(['getColumn', collection, table, column]);
			if (!_cache[stringified])
			{
				var meta:Object = getColumnMetadata(collection, table, column);
				var ColumnType:Class = StringColumn;
				if (meta[ColumnMetadata.DATA_TYPE] == DataType.DATE)
					ColumnType = DateColumn;
				else if (meta[ColumnMetadata.DATA_TYPE] == DataType.NUMBER)
					ColumnType = NumberColumn;
				if (table == TABLE_DOC_FILES)
					ColumnType = EquationColumn;
				var cachedColumn:IAttributeColumn = registerDisposableChild(_service, ColumnType == EquationColumn ? new EquationColumn() : new ColumnType(meta));
				_cache[stringified] = cachedColumn;
				
				// special case dependencies
				
				if (table == TABLE_DOC_FILES)
				{
					var eq:EquationColumn = cachedColumn as EquationColumn;
					eq.metadata.setSessionState(meta);
					(eq.requestVariable('title', ProxyColumn, true) as ProxyColumn).setInternalColumn(getCachedColumn(collection, TABLE_DOC_METADATA, COLUMN_DOC_TITLE));
					(eq.requestVariable('url', LinkableString, true) as LinkableString).value = url.value;
					(eq.requestVariable('method', LinkableString, true) as LinkableString).value = column == COLUMN_DOC_THUMBNAIL ? 'getThumbnail' : 'getDocument';
					(eq.requestVariable('collection', LinkableString, true) as LinkableString).value = collection;
					eq.equation.value = "`{ url.value }?method={ method.value }&collectionName={ collection.value }&document={ key.localName }`";
				}
				
				if (table == TABLE_TOPICS && column == COLUMN_TOPIC)
					rpc('getTopicWords', [collection], function(topicIdToWords:Object):Object {
						var topicIDs:Array = VectorUtils.getKeys(topicIdToWords);
						var topicWords:Array = topicIDs.map(function(topicID:String, i:int, a:Array):String {
							return lang('{0}: {1}', topicID, topicIdToWords[topicID].source);
						});
						var keys:Vector.<IQualifiedKey> = new Vector.<IQualifiedKey>();
						(WeaveAPI.QKeyManager as QKeyManager).getQKeysAsync(cachedColumn, getKeyType(collection), topicIDs, function():void {
							setRecords(cachedColumn, keys, Vector.<String>(topicWords));
						}, keys);
						return topicIdToWords;
					});
				
				if (table == TABLE_NODES || table == TABLE_DOC_WEIGHTS)
					getTopicDocWeights(collection);
				
				if (table == TABLE_DOC_METADATA)
					rpc('getDocMetadata', [collection, column], function(data:Object):Object {
						var keyType:String = getKeyType(collection);
						var keyStrings:Array = VectorUtils.getKeys(data);
						var keysVector:Vector.<IQualifiedKey> = new Vector.<IQualifiedKey>();
						(WeaveAPI.QKeyManager as QKeyManager).getQKeysAsync(cachedColumn, keyType, keyStrings, function():void {
							var dataVector:Vector.<String> = Vector.<String>(VectorUtils.getItems(data, keyStrings, []));
							setRecords(cachedColumn, keysVector, dataVector);
						}, keysVector);
						return data;
					});
			}
			return _cache[stringified];
		}
		
		private function getTopicIDs(collection:String):Array
		{
			var column:IAttributeColumn = getCachedColumn(collection, TABLE_TOPICS, COLUMN_TOPIC);
			return column ? (VectorUtils.pluck(column.keys, 'localName') as Array).sort() : [];
		}
		
		private function getTopicDocWeights(collection:String):Object
		{
			return rpc('getTopicDocWeights', [collection], function(topicDocWeights:Object):Object {
				var typeData:Object = {};
				var docIDs:Array = [];
				var topicIDs:Array = [];
				var weights:Array = [];
				for (var topicID:String in topicDocWeights)
				{
					typeData[topicID] = 'topic';
					for (var docID:String in topicDocWeights[topicID])
					{
						typeData[docID] = 'document';
						docIDs.push(docID);
						topicIDs.push(topicID);
						weights.push(topicDocWeights[topicID][docID]);
					}
				}
				
				var typeColumn:StringColumn = StringColumn(getCachedColumn(collection, TABLE_NODES, COLUMN_NODE_TYPE));
				var nodeIDs:Array = VectorUtils.getKeys(typeData);
				var nodeKeys:Vector.<IQualifiedKey> = new Vector.<IQualifiedKey>();
				(WeaveAPI.QKeyManager as QKeyManager).getQKeysAsync(typeColumn, getKeyType(collection), nodeIDs, function():void {
					typeColumn.setRecords(nodeKeys, Vector.<String>(VectorUtils.getItems(typeData, nodeIDs, [])));
				}, nodeKeys);
				
				topicIDs.forEach(function(topicID:String, i:int, a:Array):void {
					var keysVector:Vector.<IQualifiedKey> = new Vector.<IQualifiedKey>();
					var docIdsForTopic:Array = VectorUtils.getKeys(topicDocWeights[topicID]);
					var numberColumn:NumberColumn = NumberColumn(getCachedColumn(collection, TABLE_DOC_WEIGHTS, topicID));
					(WeaveAPI.QKeyManager as QKeyManager).getQKeysAsync(numberColumn, getKeyType(collection), docIdsForTopic, function():void {
						var dataVector:Vector.<Number> = Vector.<Number>(VectorUtils.getItems(topicDocWeights[topicID], docIdsForTopic, []));
						numberColumn.setRecords(keysVector, dataVector);
					}, keysVector);
				});
				
				addAsyncResponder(
					_rService.invokeAsyncMethod('doForceDirectedLayout', [docIDs, topicIDs, weights, null, null, null, null]),
					function(event:ResultEvent, token:Object = null):void {
						// returns nodeId -> [x, y]
						var nodeIdToXY:Object = event.result;
						var keys:Array = VectorUtils.getKeys(nodeIdToXY);
						var outputKeys:Vector.<IQualifiedKey> = new Vector.<IQualifiedKey>();
						(WeaveAPI.QKeyManager as QKeyManager).getQKeysAsync(_rService, getKeyType(collection), keys, function():void {
							var values:Array = VectorUtils.getItems(nodeIdToXY, keys, []);
							NumberColumn(getCachedColumn(collection, TABLE_NODES, COLUMN_NODE_X)).setRecords(outputKeys, Vector.<Number>(VectorUtils.pluck(values, '0')));
							NumberColumn(getCachedColumn(collection, TABLE_NODES, COLUMN_NODE_Y)).setRecords(outputKeys, Vector.<Number>(VectorUtils.pluck(values, '1')));
						}, outputKeys);
					}
				);
				return topicDocWeights;
			});
		}
		
		// avoids recreating collection categories (tree collapse bug)
		private const _listCollectionsCallbacks:ICallbackCollection = newLinkableChild(this, CallbackCollection);
		
		/**
		 * Gets the root node of the attribute hierarchy.
		 */
		override public function getHierarchyRoot():IWeaveTreeNode
		{
			var source:DocumentMapDataSource = this;
			if (!_rootNode)
				_rootNode = new ColumnTreeNode({
					source: _listCollectionsCallbacks, // avoids recreating collection categories (tree collapse bug)
					data: {source: source},
					label: WeaveAPI.globalHashMap.getName(this),
					isBranch: true,
					children: function():Array {
						return rpc('listCollections', [], function(collections:Array):Array {
							_listCollectionsCallbacks.triggerCallbacks(); // avoids recreating collection categories (tree collapse bug)
							return collections.map(function(collection:String, i:int, a:Array):* {
								var keyType:String = getKeyType(collection);

								return {
									source: _listCollectionsCallbacks, // avoids recreating collection categories (tree collapse bug)
									data: {source: source, collection: collection},
									isBranch: true,
									hasChildBranches: true,
									label: collection,
									children: [
										{
											source: _listCollectionsCallbacks, // avoids recreating collection categories (tree collapse bug)
											data: {source: source, collection: collection, table: 'topics'},
											isBranch: true,
											hasChildBranches: false,
											label: lang('Topics'),
											children: getColumnNodeDescriptors(collection, TABLE_TOPICS, [
												COLUMN_TOPIC
											])
										},
										{
											source: source, // causes children refresh when data source triggers callbacks
											data: {source: source, collection: collection, table: 'documents'},
											isBranch: true,
											hasChildBranches: false,
											label: lang('Documents'),
											children: function():Array {
												return [].concat(
													getColumnNodeDescriptors(collection, TABLE_DOC_METADATA, [
														COLUMN_DOC_TITLE,
														COLUMN_DOC_MODIFIED_TIME
													]),
													getColumnNodeDescriptors(collection, TABLE_DOC_FILES, [
														COLUMN_DOC_URL,
														COLUMN_DOC_THUMBNAIL
													]),
													getColumnNodeDescriptors(collection, TABLE_DOC_WEIGHTS, getTopicIDs(collection))
												);
											}
										},
										{
											source: _listCollectionsCallbacks, // avoids recreating collection categories (tree collapse bug)
											data: {source: source, collection: collection, table: 'nodes'},
											isBranch: true,
											hasChildBranches: false,
											label: lang('Nodes'),
											children: getColumnNodeDescriptors(collection, TABLE_NODES, [
												COLUMN_NODE_TYPE,
												COLUMN_NODE_X,
												COLUMN_NODE_Y
											])
										}
									]
								};
							});
						});
					}
				});
			
			return _rootNode;
		}
		
		override protected function generateHierarchyNode(metadata:Object):IWeaveTreeNode
		{
			if (!metadata)
				return null;
			
			return new ColumnTreeNode({source: this, columnMetadata: metadata});
		}
		
		private function handleFault(event:FaultEvent, token:Object = null):void
		{
			if (objectWasDisposed(_service))
				return;
			reportError(event);
			trace('async token',ObjectUtil.toString(token));
		}
		
		/**
		 * @inheritDoc
		 */
		override protected function requestColumnFromSource(proxyColumn:ProxyColumn):void
		{
			var metadata:Object = proxyColumn.getProxyMetadata()
			var collection:String = metadata[META_COLLECTION];
			var table:String = metadata[META_TABLE];
			var column:String = metadata[META_COLUMN];

			var cachedColumn:IAttributeColumn = getCachedColumn(collection, table, column);
			if (cachedColumn)
			{
				proxyColumn.setInternalColumn(cachedColumn);
				proxyColumn.setMetadata(getColumnMetadata(collection, table, column));
			}
			else
				proxyColumn.dataUnavailable();
		}
		
		private function setRecords(column:IAttributeColumn, keysVector:Vector.<IQualifiedKey>, dataVector:*):void
		{
			if (column is NumberColumn)
				(column as NumberColumn).setRecords(keysVector, dataVector);
			else if (column is DateColumn)
				(column as DateColumn).setRecords(keysVector, dataVector);
			else if (column is StringColumn)
				(column as StringColumn).setRecords(keysVector, dataVector);
			else
				throw new Error("Unsupported column type " + getQualifiedClassName(column));
		}
	}
}
