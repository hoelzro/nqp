var sixmodel = require('./sixmodel.js');

function basic_type_object_for(HOW) {
  var st = new sixmodel.STable(this, HOW);
  this._STable = st;
  var obj = new st.obj_constructor();

  /*st.WHAT = obj;
  sixmodel.mark_as_type_object(obj);*/
  return obj;
}

function basic_allocate(STable) {
  return new STable.obj_constructor()
}

function P6opaque() {
}

P6opaque.prototype.allocate = basic_allocate;


P6opaque.prototype.deserialize_repr_data = function(cursor) {
  this.deserialized = 1;
  var num_attributes = cursor.varint();
  this.flattened_stables = [];
  for (var i = 0; i < num_attributes; i++) {
    var not_null = cursor.varint();
    this.flattened_stables.push(not_null != 0 ? cursor.sc.deps[cursor.I32()].root_stables[cursor.I32()] : null);
  }
  this.mi = cursor.varint();
  var has_auto_viv_values = cursor.varint();
  if (has_auto_viv_values != 0) {
    this.auto_viv_values = [];
    for (var i = 0; i < num_attributes; i++) {
      this.auto_viv_values.push(cursor.variant());
    }
  }

  this.unbox_int_slot = cursor.varint();
  this.unbox_num_slot = cursor.varint();
  this.unbox_str_slot = cursor.varint();



  var has_unbox_slots = cursor.varint();

  if (has_unbox_slots != 0) {
    this.unbox_slots = [];
    for (var i = 0; i < num_attributes; i++) {
      var repr_id = cursor.varint();
      var slot = cursor.varint();
      this.unbox_slots.push({slot: slot, repr_id: repr_id});
    }
  }

  var num_classes = cursor.varint();
  this.name_to_index_mapping = [];

  for (var i = 0; i < num_classes; i++) {
      this.name_to_index_mapping[i] = {slots: [], names: [], class_key: cursor.variant()};

      var num_attrs = cursor.varint();

      for (var j = 0; j < num_attrs; j++) {
          this.name_to_index_mapping[i].names[j] = cursor.str();
          this.name_to_index_mapping[i].slots[j] = cursor.varint();
      }
  }

  /* TODO make possitional and associative delegates work */
  /* TODO make auto viv values work */
};

P6opaque.prototype.deserialize_finish = function(object, data) {
  var attrs = [];

  for (var i = 0; i < this.flattened_stables.length; i++) {
    if (this.flattened_stables[i]) {
      var STable = this.flattened_stables[i];
      var flattened_object = STable.REPR.allocate(STable);
      STable.REPR.deserialize_finish(flattened_object, data);

      attrs.push(flattened_object);
    } else {
      attrs.push(data.variant());
    }
  }
  for (var i in this.name_to_index_mapping) {
    for (var j in this.name_to_index_mapping[i].slots) {
        var name = this.name_to_index_mapping[i].names[j];
        var slot = this.name_to_index_mapping[i].slots[j];
        // TODO take class key into account with attribute storage
        object[name] = attrs[slot];
    }
  }
};

module.exports.P6opaque = P6opaque;

function KnowHOWREPR() {
}

KnowHOWREPR.prototype.deserialize_finish = function(object, data) {
  object.__name = data.str();
  object.__attributes = data.variant();
  object.__methods = data.variant();
};

KnowHOWREPR.prototype.type_object_for = basic_type_object_for;
KnowHOWREPR.prototype.allocate = basic_allocate;
module.exports.KnowHOWREPR = KnowHOWREPR;

function KnowHOWAttribute() {
}
KnowHOWAttribute.prototype.deserialize_finish = function(object, data) {
  object.__name = data.str();
};

KnowHOWAttribute.prototype.type_object_for = basic_type_object_for;
KnowHOWAttribute.prototype.allocate = basic_allocate;
module.exports.KnowHOWAttribute = KnowHOWAttribute;

function Uninstantiable() {
}
Uninstantiable.prototype.type_object_for = basic_type_object_for;
module.exports.Uninstantiable = Uninstantiable;


