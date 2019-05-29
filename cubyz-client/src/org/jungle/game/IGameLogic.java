package org.jungle.game;

import org.jungle.Window;

public interface IGameLogic {

    void init(Window window) throws Exception;
    
    void input(Window window);
    
    void update(float interval);
    
    void render(Window window);
    
    void bind(Game g);
    
    void cleanup();
}
