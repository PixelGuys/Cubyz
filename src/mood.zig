pub const Mood = struct {
	anxiety: f32 = 0.3,
	energy: f32 = 0.3,
	sanity: f32 = 0.7,

	pub fn distanceTo(self: Mood, other: Mood) f32 {
		const da = self.anxiety - other.anxiety;
		const de = self.energy - other.energy;
		const ds = self.sanity - other.sanity;
		return @sqrt(da*da + de*de + ds*ds);
	}
};
