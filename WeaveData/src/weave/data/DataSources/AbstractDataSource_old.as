/* ***** BEGIN LICENSE BLOCK *****
 *
 * This file is part of Weave.
 *
 * The Initial Developer of Weave is the Institute for Visualization
 * and Perception Research at the University of Massachusetts Lowell.
 * Portions created by the Initial Developer are Copyright (C) 2008-2015
 * the Initial Developer. All Rights Reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 * 
 * ***** END LICENSE BLOCK ***** */

package weave.data.DataSources
{
	import weave.api.detectLinkableObjectChange;
	import weave.api.getCallbackCollection;
	import weave.api.newLinkableChild;
	import weave.api.core.ICallbackCollection;
	import weave.api.data.IWeaveTreeNode;
	import weave.core.LinkableXML;
	import weave.data.hierarchy.XMLEntityNode;
	import weave.utils.HierarchyUtils;
	
	/**
	 * This is a base class to make it easier to develope a new class that implements IDataSource_old.
	 * getHierarchyRoot() and generateHierarchyNode() should be overridden if the data source does not use XMLEntityNode to build its hierarchy.
	 * 
	 * @author adufilie
	 */
	public class AbstractDataSource_old extends AbstractDataSource implements IDataSource_old
	{
		public function AbstractDataSource_old()
		{
			var cc:ICallbackCollection = getCallbackCollection(this);
			cc.addImmediateCallback(this, uninitialize);
			cc.addGroupedCallback(this, initialize, true);
		}
		
		/**
		 * This function must be implemented by classes that extend AbstractDataSource.
		 * It will be called the frame after the session state for the data source changes.
		 * When overriding this function, super.initialize() should be called.
		 */
		override protected function initialize(forceRefresh:Boolean = false):void
		{
			// set initialized to true so other parts of the code know if this function has been called.
			_initializeCalled = true;

			// TODO: check each column previously provided by getAttributeColumn()

			// initialize hierarchy if it is null
			if (_attributeHierarchy.value == null && detectLinkableObjectChange(_requestedHierarchySubtreeStringMap, _attributeHierarchy))
			{
				// Clear the list of requested hierarchy subtrees.
				// This will allow the hierarchy to be filled in automatically
				// if its contents were cleared with that intention.
				_requestedHierarchySubtreeStringMap = {};
				detectLinkableObjectChange(_requestedHierarchySubtreeStringMap, _attributeHierarchy);
				initializeHierarchySubtree(null);
			}
			
			if (forceRefresh)
				refreshAllProxyColumns(initializationComplete);
			else
				handleAllPendingColumnRequests(initializationComplete);
		}
		
		/**
		 * This function must be implemented by classes by extend AbstractDataSource.
		 * This function should make a request to the source to fill in the hierarchy at the given subtree.
		 * This function will only be called once per subtreeNode.
		 * @param subtreeNode A pointer to a node in the hierarchy representing the root of the subtree to request from the source.
		 */
		/* abstract */ protected function requestHierarchyFromSource(subtreeNode:XML = null):void { }

		/**
		 * @inheritDoc
		 */
		override protected function refreshHierarchy():void
		{
			_rootNode = null;
			_attributeHierarchy.setSessionState(null);
		}

		/**
		 * @inheritDoc
		 */
		override public function getHierarchyRoot():IWeaveTreeNode
		{
			if (!(_rootNode is XMLEntityNode))
				_rootNode = new XMLEntityNode();
			(_rootNode as XMLEntityNode).dataSourceName = WeaveAPI.globalHashMap.getName(this);
			(_rootNode as XMLEntityNode).xml = _attributeHierarchy.value;
			return _rootNode;
		}

		/**
		 * This function should be overridden if the data source does not use XMLEntityNode for its hierarchy nodes.
		 */
		override protected function generateHierarchyNode(metadata:Object):IWeaveTreeNode
		{
			if (!metadata)
				return null;
			return new XMLEntityNode(WeaveAPI.globalHashMap.getName(this), HierarchyUtils.nodeFromMetadata(metadata));
		}
		
		/**
		 * @return An AttributeHierarchy object that will be updated when new pieces of the hierarchy are filled in.
		 */
		public function get attributeHierarchy():LinkableXML
		{
			return _attributeHierarchy;
		}

		// this is returned by a public getter
		protected var _attributeHierarchy:LinkableXML = newLinkableChild(this, LinkableXML, handleHierarchyChange);

		/**
		 * This maps a requested hierarchy subtree xml string to a value of true.
		 * If a subtree node has not been requested yet, it will not appear in this Object.
		 */
		protected var _requestedHierarchySubtreeStringMap:Object = new Object();
		
		/**
		 * If the hierarchy subtree pointed to subtreeNode 
		 * @param subtreeNode A pointer to a node in the hierarchy representing the root of the subtree to request from the source.
		 */
		public function initializeHierarchySubtree(subtreeNode:XML = null):void
		{
			var pathString:String = '';
			if (subtreeNode == null)
			{
				// do nothing if root node already has children
				if (_attributeHierarchy.value != null && _attributeHierarchy.value.children().length() > 0)
					return;
			}
			else
			{
				var path:XML = HierarchyUtils.getPathFromNode(_attributeHierarchy.value, subtreeNode);
				// do nothing if path does not exist or node already has children
				if (path == null || subtreeNode.children().length() > 0)
					return;
				pathString = path.toXMLString();
			}
			if (_requestedHierarchySubtreeStringMap[pathString] == undefined)
			{
				_requestedHierarchySubtreeStringMap[pathString] = true;
				WeaveAPI.StageUtils.callLater(this, requestHierarchyFromSource, [subtreeNode]);
			}
		}

		/**
		 * This function gets called when the hierarchy callbacks are run.
		 * This function can be defined with override by classes that extend AbstractDataSource.
		 */
		protected function handleHierarchyChange():void
		{
		}
	}
}
