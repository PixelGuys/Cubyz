package cubyz.utils.datastructures;

import java.util.HashMap;
import java.util.function.Consumer;
import java.util.function.Supplier;

public class Tree<Key, Value> {
	public class TreeNode {
		private final HashMap<Key, TreeNode> nextNodes = new HashMap<Key, TreeNode>();
		private final HashMap<Key, Value> leaves = new HashMap<Key, Value>();
		
		@SuppressWarnings("unchecked")
		private void foreach(Consumer<Value> action) {
			for(Object value : leaves.values().toArray()) {
				action.accept((Value)value);
			}
			for(Object next : nextNodes.values().toArray()) {
				((TreeNode)next).foreach(action);
			}
		}
	}
	TreeNode root = new TreeNode();
	public void add(Key[] keys, Value value) {
		TreeNode node = root;
		for(int i = 0; i < keys.length-1; i++) {
			TreeNode nextNode = node.nextNodes.get(keys[i]);
			if (nextNode == null) {
				nextNode = new TreeNode();
				node.nextNodes.put(keys[i], nextNode);
			}
			node = nextNode;
		}
		node.leaves.put(keys[keys.length-1], value);
	}
	public Value get(Key[] keys) {
		TreeNode node = root;
		for(int i = 0; i < keys.length-1; i++) {
			node = node.nextNodes.get(keys[i]);
			if (node == null) {
				return null;
			}
		}
		return node.leaves.get(keys[keys.length-1]);
	}
	public Value getOrAdd(Key[] keys, Supplier<Value> constructor) {
		TreeNode node = root;
		for(int i = 0; i < keys.length-1; i++) {
			TreeNode nextNode = node.nextNodes.get(keys[i]);
			if (nextNode == null) {
				nextNode = new TreeNode();
				node.nextNodes.put(keys[i], nextNode);
			}
			node = nextNode;
		}
		Value ret = node.leaves.get(keys[keys.length-1]);
		if (ret != null) return ret;
		ret = constructor.get();
		node.leaves.put(keys[keys.length-1], ret);
		return ret;
	}
	
	public void foreach(Consumer<Value> action) {
		root.foreach(action);
	}
}
