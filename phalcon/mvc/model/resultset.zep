
/*
 +------------------------------------------------------------------------+
 | Phalcon Framework                                                      |
 +------------------------------------------------------------------------+
 | Copyright (c) 2011-2015 Phalcon Team (http://www.phalconphp.com)       |
 +------------------------------------------------------------------------+
 | This source file is subject to the New BSD License that is bundled     |
 | with this package in the file docs/LICENSE.txt.                        |
 |                                                                        |
 | If you did not receive a copy of the license and are unable to         |
 | obtain it through the world-wide-web, please send an email             |
 | to license@phalconphp.com so we can send you a copy immediately.       |
 +------------------------------------------------------------------------+
 | Authors: Andres Gutierrez <andres@phalconphp.com>                      |
 |          Eduar Carvajal <eduar@phalconphp.com>                         |
 +------------------------------------------------------------------------+
 */

namespace Phalcon\Mvc\Model;

use Phalcon\Mvc\Model;
use Phalcon\Cache\BackendInterface;
use Phalcon\Mvc\ModelInterface;
use Phalcon\Mvc\Model\Exception;
use Phalcon\Mvc\Model\ResultsetInterface;

/**
 * Phalcon\Mvc\Model\Resultset
 *
 * This component allows to Phalcon\Mvc\Model returns large resulsets with the minimum memory consumption
 * Resulsets can be traversed using a standard foreach or a while statement. If a resultset is serialized
 * it will dump all the rows into a big array. Then unserialize will retrieve the rows as they were before
 * serializing.
 *
 * <code>
 *
 * //Using a standard foreach
 * $robots = Robots::find(array("type='virtual'", "order" => "name"));
 * foreach ($robots as robot) {
 *  echo robot->name, "\n";
 * }
 *
 * //Using a while
 * $robots = Robots::find(array("type='virtual'", "order" => "name"));
 * $robots->rewind();
 * while ($robots->valid()) {
 *  $robot = $robots->current();
 *  echo $robot->name, "\n";
 *  $robots->next();
 * }
 * </code>
 */
abstract class Resultset
	implements ResultsetInterface, \Iterator, \SeekableIterator, \Countable, \ArrayAccess, \Serializable
{

	protected _type = 0;

	protected _result;

	protected _cache;

	protected _isFresh = true;

	protected _pointer = 0;

	protected _count;

	protected _activeRow = null;

	protected _rows = null;
	
	protected _row = null;

	protected _errorMessages;

	protected _hydrateMode = 0;

	const TYPE_RESULT_FULL = 0;

	const TYPE_RESULT_PARTIAL = 1;

	const HYDRATE_RECORDS = 0;

	const HYDRATE_OBJECTS = 2;

	const HYDRATE_ARRAYS = 1;

	/**
	 * Moves cursor to next row in the resultset
	 */
	public function next() -> void
	{
		// Seek to the next position
		this->seek(this->_pointer + 1);
	}
	
	/**
	 * Check whether internal resource has rows to fetch
	 */
	public function valid() -> boolean
	{		
		return this->_pointer < this->count();
	}

	/**
	 * Gets pointer number of active row in the resultset
	 */
	public function key() -> int | null
	{		
		if this->_pointer >= this->count() {
			return null;
		}

		return this->_pointer;
	}

	/**
	 * Rewinds resultset to its beginning
	 */
	public final function rewind() -> void
	{		
		this->seek(0);
	}

	/**
	 * Changes internal pointer to a specific position in the resultset
	 */
	public final function seek(int position) -> void
	{
		var result;
		
		if this->_type {
			/**
			* Fetch from PDO one-by-one. Set new position if required and set this->_row
			*/
			if this->_row === null || this->_pointer != position {
				let result = this->_result;
				if result !== false {
				    if this->_row === null && this->_pointer === 0 {
				    	/**
			            * Fresh result-set: Query was already executed in model\query::_executeSelect()
			            * The first row is available with fetch
			            */
				        let this->_row = result->$fetch(result);
				    }

					if this->_pointer > position {
					    /**
					    * Current pointer is ahead requested position: e.g. request a previous row
					    * It is not possible to rewind. Re-execute query with dataSeek
					    */
						result->dataSeek(position);
						let this->_row = result->$fetch(result);
						let this->_pointer = position;
					}

                    while this->_pointer < position {
                        /**
						* Requested position is greater than current pointer,
						* seek forward until the requested position is reached.
						* We do not need to re-execute the query!
						*/
                        let this->_row = result->$fetch(result);
                        let this->_pointer++;
                    }
				}
				
				let this->_pointer = position;
				let this->_activeRow = null;
			}
		} else {
			/**
			* Reset activeRow for simple arrays if new position requested
			*/
			if this->_pointer != position {
				let this->_pointer = position;
				let this->_activeRow = null;
			}
		}
	}

	/**
	 * Counts how many rows are in the resultset
	 */
	public final function count() -> int
	{
		var count, result, rows;

		let count = this->_count;

		/**
		 * We only calculate the row number if it wasn't calculated before
		 */
		if typeof count === "null" {
			let count = 0;
			if this->_type {

				/**
				 * Here, the resultset act as a result that is fetched one by one
				 */
				let result = this->_result;
				if result !== false {
					let count = intval(result->numRows());
				}
			} else {

				/**
				 * Here, the resultset act as an array
				 */
				let rows = this->_rows;
				if rows === null {
					let result = this->_result;
					if typeof result == "object" {
						let rows = result->fetchAll(),
							this->_rows = rows;
					}
				}
				let count = count(rows);
			}
			let this->_count = count;
		}
		return count;
	}

	/**
	 * Checks whether offset exists in the resultset
	 */
	public function offsetExists(int index) -> boolean
	{
		return index < this->count();
	}

	/**
	 * Gets row in a specific position of the resultset
	 */
	public function offsetGet(int! index) -> <ModelInterface> | boolean
	{
		if index < this->count() {
	   		/**
	   		 * Move the cursor to the specific position
	   		 */
			this->seek(index);
			
			return this->{"current"}();
			
		}
		throw new Exception("The index does not exist in the cursor");
	}

	/**
	 * Resulsets cannot be changed. It has only been implemented to meet the definition of the ArrayAccess interface
	 *
	 * @param int index
	 * @param Phalcon\Mvc\ModelInterface value
	 */
	public function offsetSet(var index, var value)
	{
		throw new Exception("Cursor is an immutable ArrayAccess object");
	}

	/**
	 * Resulsets cannot be changed. It has only been implemented to meet the definition of the ArrayAccess interface
	 */
	public function offsetUnset(int offset)
	{
		throw new Exception("Cursor is an immutable ArrayAccess object");
	}

	/**
	 * Returns the internal type of data retrieval that the resultset is using
	 */
	public function getType() -> int
	{
		return this->_type;
	}

	/**
	 * Get first row in the resultset
	 */
	public function getFirst() -> <ModelInterface> | boolean
	{		
		if this->count() == 0 {
			return false;
		}

		this->seek(0);
		return this->{"current"}();
	}

	/**
	 * Get last row in the resultset
	 */
	public function getLast() -> <ModelInterface> | boolean
	{		
		var count;
		let count = this->count();	
		if count == 0 {
			return false;
		}
		
		this->seek(count - 1);
		return this->{"current"}();
	}

	/**
	 * Set if the resultset is fresh or an old one cached
	 */
	public function setIsFresh(boolean isFresh) -> <Resultset>
	{
		let this->_isFresh = isFresh;
		return this;
	}

	/**
	 * Tell if the resultset if fresh or an old one cached
	 */
	public function isFresh() -> boolean
	{
		return this->_isFresh;
	}

	/**
	 * Sets the hydration mode in the resultset
	 */
	public function setHydrateMode(int hydrateMode) -> <Resultset>
	{
		let this->_hydrateMode = hydrateMode;
		return this;
	}

	/**
	 * Returns the current hydration mode
	 */
	public function getHydrateMode() -> int
	{
		return this->_hydrateMode;
	}

	/**
	 * Returns the associated cache for the resultset
	 */
	public function getCache() -> <BackendInterface>
	{
		return this->_cache;
	}

	/**
	 * Returns the error messages produced by a batch operation
	 */
	public function getMessages() -> <\Phalcon\Mvc\Model\MessageInterface[]>
	{
		return this->_errorMessages;
	}

	/**
	 * Updates every record in the resultset
	 *
	 * @param array data
	 * @param Closure conditionCallback
	 * @return boolean
	 */
	public function update(var data, <\Closure> conditionCallback = null) -> boolean
	{
		boolean transaction;
		var record, connection = null;

		let transaction = false;
		for record in iterator(this) {

			if transaction === false {

				/**
				 * We only can update resultsets if every element is a complete object
				 */
				if !method_exists(record, "getWriteConnection") {
					throw new Exception("The returned record is not valid");
				}

				let connection = record->getWriteConnection(),
					transaction = true;
				connection->begin();
			}

			/**
			 * Perform additional validations
			 */
			if typeof conditionCallback == "object" {
				if call_user_func_array(conditionCallback, [record]) === false {
					continue;
				}
			}

			/**
			 * Try to update the record
			 */
			if !record->save(data) {

				/**
				 * Get the messages from the record that produce the error
				 */
				let this->_errorMessages = record->getMessages();

				/**
				 * Rollback the transaction
				 */
				connection->rollback();
				let transaction = false;
				break;
			}
		}

		/**
		 * Commit the transaction
		 */
		if transaction === true {
			connection->commit();
		}

		return true;
	}

	/**
	 * Deletes every record in the resultset
	 */
	public function delete(<\Closure> conditionCallback = null) -> boolean
	{
		boolean transaction;
		var record, connection = null;

		let transaction = false;
		for record in iterator(this) {

			if transaction === false {

				/**
				 * We only can delete resultsets if every element is a complete object
				 */
				if !method_exists(record, "getWriteConnection") {
					throw new Exception("The returned record is not valid");
				}

				let connection = record->getWriteConnection(),
					transaction = true;
				connection->begin();
			}

			/**
			 * Perform additional validations
			 */
			if typeof conditionCallback == "object" {
				if call_user_func_array(conditionCallback, [record]) === false {
					continue;
				}
			}

			/**
			 * Try to delete the record
			 */
			if !record->delete() {

				/**
				 * Get the messages from the record that produce the error
				 */
				let this->_errorMessages = record->getMessages();

				/**
				 * Rollback the transaction
				 */
				connection->rollback();
				let transaction = false;
				break;
			}
		}

		/**
		 * Commit the transaction
		 */
		if transaction === true {
			connection->commit();
		}

		return true;
	}

	/**
	 * Filters a resultset returning only those the developer requires
	 *
	 *<code>
	 * $filtered = $robots->filter(function($robot){
	 *		if ($robot->id < 3) {
	 *			return $robot;
	 *		}
	 *	});
	 *</code>
	 *
	 * @param callback filter
	 * @return Phalcon\Mvc\Model[]
	 */
	public function filter(var filter) -> array
	{
		var records, record, parameters, processedRecord;

		let records = [],
			parameters = [];

		for record in iterator(this) {

			let parameters[0] = record,
				processedRecord = call_user_func_array(filter, parameters);

			/**
			 * Only add processed records to 'records' if the returned value is an array/object
			 */
			if typeof processedRecord != "object" {
				if typeof processedRecord != "array" {
					continue;
				}
			}

			let records[] = processedRecord;
		}

		return records;
	}
}
