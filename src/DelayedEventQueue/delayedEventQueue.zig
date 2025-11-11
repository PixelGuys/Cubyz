const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const blocks = main.blocks;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;
const Server = main.server;

pub const Event = struct{
    x:i32,
    y:i32,
    z:i32,

    //was something done?
    pub fn run(self:*const Event)bool{
        main.items.Inventory.Sync.ServerSide.mutex.lock();
	    defer main.items.Inventory.Sync.ServerSide.mutex.unlock();

        if(Server.world)|world|{
            if(world.getBlock(self.x, self.y, self.z))|leave|{
                if(leave.decayable()){
                    //check if there is any log in the proximity?
                    const checkRange = 3;
                    var   logFound  :bool = false;
                    blk: for (0..checkRange*2+1) |offsetX| {
                        for (0..checkRange*2+1) |offsetY| {
                            for (0..checkRange*2+1) |offsetZ| {
                                const x = self.x+@as(i32,@intCast(offsetX))-checkRange;
                                const y = self.y+@as(i32,@intCast(offsetY))-checkRange;
                                const z = self.z+@as(i32,@intCast(offsetZ))-checkRange;
                                if(world.getBlock(x, y, z))|log|{
                                    if(log.decayProhibitor()){
                                        logFound = true;
                                        break :blk;
                                    }
                                }
                            }
                        }
                    }
                    if(logFound)
                        return false;
                    //no, there is no log in proximity
                    world.updateBlock(self.x,self.y,self.z, main.blocks.Block.air);
                    
                    //trigger others:
                    const logRange = 1;
                    for (0..logRange*2+1) |offsetX| {
                        for (0..logRange*2+1) |offsetY| {
                            for (0..logRange*2+1) |offsetZ| {
                                const x = self.x+@as(i32,@intCast(offsetX))-logRange;
                                const y = self.y+@as(i32,@intCast(offsetY))-logRange;
                                const z = self.z+@as(i32,@intCast(offsetZ))-logRange;
                                if(x != self.x or y != self.y or self.z != z){
                                    world.delayedEventQueue.pushBack(.{
                                        .x = x,
                                        .y = y,
                                        .z = z,
                                    });
                                }
                                    //world.updateBlock(x,y,z, param.block);
                            }
                        }
                    }
                    return true;
                }
            }
        }
        return false;
        //std.debug.print("hello! {d} {d} {d}\n", .{self.x,self.y,self.z});
    }
};