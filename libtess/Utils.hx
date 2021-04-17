package libtess;

@:native
@:nativeChildren
@:nativeProperty
@:nativeGen
@:expose('libtess.Utils')
class Utils {
    static var DEBUG = false;


     static public function assert(condition:Bool, opt_message:String = "") {
        if (Utils.DEBUG && !condition) {
          throw ('Assertion failed' + opt_message );
        }
    };

    static public function isDebug() {
        return Utils.DEBUG;
    };
}