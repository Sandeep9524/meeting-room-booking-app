public class BugDemo {

    public static void testBug(){

        String s = 'Agentforce';

        if(s != null){
            System.debug(s.length());
        }
    }
}