package cubyz.utils.algorithms;

public abstract class StringOperation {
    public static String escape(String string){
        return string   .replace("\\", "\\\\") //escaping  \
                        .replace("\n", "\\\n") //escaping new line
                        .replace("\"", "\\\"") //escaping "
                        .replace("\t", "\\t")  //escaping  tabs
                ;
    }
}
