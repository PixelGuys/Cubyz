package cubyz.utils;

/**
 * Try to run a function `update` only once every x timeunits.
 * (Not multithreaded)
 */
public abstract class Pacer {
    public boolean running = true;
    private int frequency = 20;
    private long previousTime = System.nanoTime();
    private String threadName;

    public abstract void update();

    public Pacer(String threadName){
        this.threadName = threadName;
        updateCachedPeriodTimes();
    }
    public void start() throws InterruptedException {
        while (running){
            update();
            // Sync:
            if (System.nanoTime() - previousTime < cached_periodTimeNanoSec) {
                Thread.sleep((cached_periodTimeNanoSec - (System.nanoTime() - previousTime))/1000000);
                previousTime += cached_periodTimeNanoSec;
            } else {
                Logger.warning(threadName.concat(" is lagging behind."));
                previousTime = System.nanoTime();
            }
        }
    }

    //cached stuff
    public int cached_periodTimeNanoSec = 1_000_000_000 / frequency;
    private void updateCachedPeriodTimes() {
        cached_periodTimeNanoSec = 1_000_000_000 / frequency;
    }

    //set / get
    public void setFrequency(int frequencySeconds){
        frequency = frequencySeconds;
        updateCachedPeriodTimes();
    }


}
