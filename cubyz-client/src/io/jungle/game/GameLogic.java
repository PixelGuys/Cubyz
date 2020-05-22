package io.jungle.game;

import io.jungle.Window;

public interface GameLogic {

    void init(Window window) throws Exception;
    
    void input(Window window);
    
    void update(float interval);
    
    void render(Window window);
    
    void bind(Game g);
    
    void cleanup();
}
