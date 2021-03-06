/**
 * A serialization context holds a list of objects and code references that live
 * within a serialization boundary.
 */



/**
 * @constructor
 * @property handle The handle of this SC.
 * @property description Description (probably the file name) if any.
 * @property root_objects The root set of objects that live in this SC.
 * @property root_stables The root set of STables that live in this SC.
 * @property root_codes The root set of code refs that live in this SC.
 * @property rep_indexes Repossession info. The following lists have matching indexes, each
 * representing the integer of an object in our root set along with the SC
 * that the object was originally from.
 * @property rep_scs
*/
function SerializationContext(handle) {
  this.description = '???';
  this.handle = handle;
  this.root_objects = [];
  this.root_stables = [];
  this.root_codes = [];
  this.rep_indexes = [];
  this.rep_scs = [];
  /* Some things we deserialize are not directly in an SC, root set, but
   * rather are owned by others. This is mostly thanks to Parrot legacy,
   * where not everything was a 6model object. This maps such owned
   * objects to their owner. It is used to determine what object should
   * be repossessed in the case a write barrier is hit. */
  //  this.owned_objects = new HashMap<SixModelObject, SixModelObject>();
}

/* Takes an object and adds it to this SC's root set, and installs a
 * reposession entry. */
SerializationContext.prototype.repossessObject = function(origSC, obj) {
  /* Check the object really lives in the SC root set. */
  if (obj.sc.root_objects.indexOf(obj) < 0)
    throw 'Attempt to repossess object not in this context';

  /* Add to root set. */
  var newSlot = root_objects.length;
  root_objects.push(obj);

  /* Add repossession entry. */
  rep_indexes.push(newSlot << 1);
  rep_scs.push(origSC);
};

/* Takes an STable and adds it to this SC's root set, and installs a
 * reposession entry. */
SerializationContext.prototype.repossessSTable = function(origSC, st) {
  /* Add to root set. */
  var newSlot = root_stables.size();
  root_stables.push(st);

  /* Add repossession entry. */
  rep_indexes.push((newSlot << 1) | 1);
  rep_scs.push(origSC);
};
module.exports = SerializationContext;
