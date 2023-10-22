const std = @import("std");

const main = @import("root");
const random = main.random;

fn getSeedX(x: f32, worldSeed: u64) u64 {
	return worldSeed ^ @as(u64, 54275629861)*%@as(u32, @bitCast(@as(i32, @intFromFloat(x))));
}

fn getSeedY(x: f32, worldSeed: u64) u64 {
	return worldSeed ^ @as(u64, 5478938690717)*%@as(u32, @bitCast(@as(i32, @intFromFloat(x))));
}

fn getGridValue1D(x: f32, worldSeed: u64) f32 {
	var seed: u64 = getSeedX(x, worldSeed);
	return random.nextFloat(&seed);
}

fn samplePoint1D(_x: f32, lineSeed: u64) f32 {
	var seed = lineSeed;
	const x = _x + 0.0001*random.nextFloat(&seed); // random offset
	const start = @floor(x);
	const interp = x - start;
	return (1 - interp)*getGridValue1D(start, lineSeed) + interp*getGridValue1D(start + 1, lineSeed);
}

/// The result will be between 0 and 1.
pub fn samplePoint2D(x: f32, _y: f32, worldSeed: u64) f32 {
	var seed = worldSeed;
	const y = _y + random.nextFloat(&seed); // random offset
	const lineSeed = random.nextInt(u64, &seed);

	const start = @floor(y);
	const interp = y - start;
	const lower = samplePoint1D(x, getSeedY(start, lineSeed));
	const upper = samplePoint1D(x, getSeedY(start+1, lineSeed));
	return (1 - interp)*lower + interp*upper;
}

const percentileTable = [_]f32 {0.0e+00, 9.15669277e-02, 1.18274688e-01, 1.37655034e-01, 1.53483346e-01, 1.67139247e-01, 1.79302796e-01, 1.90366283e-01, 2.00579166e-01, 2.10111454e-01, 2.19084709e-01, 2.27589413e-01, 2.35694572e-01, 2.43454873e-01, 2.50914007e-01, 2.58107364e-01, 2.65064746e-01, 2.71810621e-01, 2.78366297e-01, 2.84749507e-01, 2.90976017e-01, 2.97059237e-01, 3.03011208e-01, 3.08842420e-01, 3.14562231e-01, 3.20178955e-01, 3.25700223e-01, 3.31132620e-01, 3.36482465e-01, 3.41755270e-01, 3.46956104e-01, 3.52089852e-01, 3.57160568e-01, 3.62172454e-01, 3.67129117e-01, 3.72033983e-01, 3.76890212e-01, 3.81700843e-01, 3.86468648e-01, 3.91196310e-01, 3.95886212e-01, 4.00540769e-01, 4.05162155e-01, 4.09752458e-01, 4.14313703e-01, 4.18847769e-01, 4.23356503e-01, 4.27841603e-01, 4.32304769e-01, 4.36747610e-01, 4.41171675e-01, 4.45578455e-01, 4.49969410e-01, 4.54345911e-01, 4.58709388e-01, 4.63061153e-01, 4.67402517e-01, 4.71734791e-01, 4.76059168e-01, 4.80376929e-01, 4.84689295e-01, 4.88997489e-01, 4.93302702e-01, 4.97606158e-01, 5.01908957e-01, 5.06212413e-01, 5.10517597e-01, 5.14825820e-01, 5.19138216e-01, 5.23455977e-01, 5.27780354e-01, 5.32112598e-01, 5.36453962e-01, 5.40805697e-01, 5.45169174e-01, 5.49545705e-01, 5.53936660e-01, 5.58343470e-01, 5.62767505e-01, 5.67210376e-01, 5.71673512e-01, 5.76158583e-01, 5.80667376e-01, 5.85201442e-01, 5.89762687e-01, 5.94352960e-01, 5.98974347e-01, 6.03628933e-01, 6.08318805e-01, 6.13046467e-01, 6.17814302e-01, 6.22624933e-01, 6.27481162e-01, 6.32386028e-01, 6.37342691e-01, 6.42354607e-01, 6.47425293e-01, 6.52559041e-01, 6.57759904e-01, 6.63032710e-01, 6.68382585e-01, 6.73814952e-01, 6.79336249e-01, 6.84952974e-01, 6.90672814e-01, 6.96504056e-01, 7.02455997e-01, 7.08539247e-01, 7.14765727e-01, 7.21148967e-01, 7.27704644e-01, 7.34450578e-01, 7.41407930e-01, 7.48601317e-01, 7.56060481e-01, 7.63820827e-01, 7.71925985e-01, 7.80430734e-01, 7.89404034e-01, 7.98936367e-01, 8.09149265e-01, 8.20212841e-01, 8.32376480e-01, 8.46032440e-01, 8.61860930e-01, 8.81241500e-01, 9.07949805e-01, 1.0};

fn preGeneratePercentileTable() !void {
	const randomNumbers = 2048;
	const positions = 2048;
	const totalValues = randomNumbers*positions;
	const values = randomNumbers;
	var amount1D: [values+1] u128 = undefined;
	@memset(&amount1D, 0);
	for(0..randomNumbers+1) |a| {
		for(0..randomNumbers+1) |b| {
			for(0..positions+1) |x| {
				const val = x*a + (positions - x)*b;
				amount1D[(val*values)/totalValues] += 1;
			}
		}
	}
	var amount2D: [values+1] u128 = undefined;
	@memset(&amount2D, 0);
	for(0..randomNumbers+1) |a| {
		for(0..randomNumbers+1) |b| {
			for(0..positions+1) |x| {
				const val = x*a + (positions - x)*b;
				amount2D[(val*values)/totalValues] += amount1D[a]*amount1D[b];
			}
		}
	}
	var samples: u128 = 0;
	for(&amount2D) |val| {
		samples = try std.math.add(u128, samples, val);
	}
	std.log.info("{}", .{samples});

	var percentiles: [128] f32 = undefined;
	var current: u128 = 0;
	var i: usize = 0;
	for(&percentiles, 0..) |*_percentile, j| {
		const goal = j*samples/(percentiles.len-1);
		while(current + amount2D[i] < goal) {
			current += amount2D[i];
			i += 1;
		}
		const diff = goal - current;
		_percentile.* = (@as(f32, @floatFromInt(i)) + @as(f32, @floatFromInt(diff))/@as(f32, @floatFromInt(amount2D[i])))/2048;
	}

	for(&percentiles) |_percentile| {
		std.log.info("{}", .{_percentile});
	}
}

pub fn percentile(ratio: f32) f32 {
	std.debug.assert(ratio >= 0);
	const scaledToList = ratio*@as(f32, @floatFromInt(percentileTable.len));
	const index: u32 = @intFromFloat(scaledToList);
	if(index >= percentileTable.len-1) return 1;
	const offset = (scaledToList - @as(f32, @floatFromInt(index)));
	return (1 - offset)*percentileTable[index] + offset*percentileTable[index + 1];
}