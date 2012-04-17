/* ***** BEGIN LICENSE BLOCK *****
 *
 * This file is part of the Weave API.
 *
 * The Initial Developer of the Weave API is the Institute for Visualization
 * and Perception Research at the University of Massachusetts Lowell.
 * Portions created by the Initial Developer are Copyright (C) 2008-2012
 * the Initial Developer. All Rights Reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 * 
 * ***** END LICENSE BLOCK ***** */

package weave.api
{
	import weave.api.core.ICallbackCollection;
	import weave.api.core.ILinkableObject;
	
	/**
	 * This function will remove a grouped callback from one ILinkableObject or ICallbackCollection and add it to another.
	 * @param oldTarget The old target, which may be null.
	 * @param newTarget The new target, which may be null.
	 * @param relevantContext Corresponds to the relevantContext parameter of ICallbackCollection.addGroupedCallback().
	 * @param groupedCallback Corresponds to the groupedCallback parameter of ICallbackCollection.addGroupedCallback().
	 * @param triggerCallbackNow Corresponds to the triggerCallbackNow parameter of ICallbackCollection.addGroupedCallback().
	 * @see weave.api.core.ICallbackCollection#addGroupedCallback
	 */
	public function juggleGroupedCallback(oldTarget:ILinkableObject, newTarget:ILinkableObject, relevantContext:Object, groupedCallback:Function, triggerCallbackNow:Boolean = false):void
	{
		// do nothing if the targets are the same.
		if (oldTarget == newTarget)
			return;
		
		// remove callback from old target
		if (oldTarget)
			WeaveAPI.SessionManager.getCallbackCollection(oldTarget).removeCallback(groupedCallback);
		
		// add callback to new target
		if (newTarget)
			WeaveAPI.SessionManager.getCallbackCollection(newTarget).addGroupedCallback(relevantContext, groupedCallback, triggerCallbackNow);
	}
}
