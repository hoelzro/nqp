var sh = require('execSync');
var temp = require('temp');
var fs = require('fs');
var map = require('source-map');
var loaderUtils = require("loader-utils");

var SourceNode = map.SourceNode;
var p6source;

function toNode(chunk) {
  if (chunk.line) {
    return new SourceNode(chunk.line, 0, p6source , chunk.parts.map(function(c) {return toNode(c)}));
  } else if (typeof chunk == 'string') {
    return chunk;
  } else if (chunk instanceof Array) {
    return chunk.map(function(c) {return toNode(c)});
  } else {
      console.error(chunk);
      throw "incorrect chunk";
  }
}

module.exports = function(source) {
  var path = this.options.nqpRepo;

  var nqpRequest = loaderUtils.getRemainingRequest(this);
  var jsRequest = loaderUtils.getCurrentRequest(this);
  var query = loaderUtils.parseQuery(this.query);

  // Write our source code to a file
  var tmp = temp.openSync();
  fs.writeFileSync(tmp.path, source);

  var command = "cd "+path+";.//nqp-p " + "src/vm/js/bin/nqp-js.nqp --source-map '" + tmp.path + "'";


  var result = sh.exec(command);

  var data = JSON.parse(result.stdout);

  p6source = nqpRequest;
  var node = new SourceNode(1,0, p6source, toNode(data));
  var sourceAndMap = node.toStringWithSourceMap({file: jsRequest});
  
  var map = JSON.parse(sourceAndMap.map.toString());
  map.sourcesContent = [source];
  this.callback(null, sourceAndMap.code, map);
};
