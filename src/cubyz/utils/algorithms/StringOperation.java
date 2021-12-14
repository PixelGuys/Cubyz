package cubyz.utils.algorithms;

public abstract class StringOperation {
    public static String escape(String string){
        return string   .replace("\n", "\\\n") //escaping new line
                        .replace("\"", "\\\"") //escaping "
                        .replace("\\", "\\\\") //escaping  \
                        .replace("\t", "\\t")  //escaping  tabs
                ;
    }
}
