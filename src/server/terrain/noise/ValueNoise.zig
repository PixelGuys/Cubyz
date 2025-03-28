const std = @import("std");

const main = @import("main");
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
	const upper = samplePoint1D(x, getSeedY(start + 1, lineSeed));
	return (1 - interp)*lower + interp*upper;
}

const percentileTable = [_]f32{0.0e+00, 9.20569300e-02, 1.18748918e-01, 1.38117700e-01, 1.53936773e-01, 1.67584523e-01, 1.79740771e-01, 1.90797567e-01, 2.01004371e-01, 2.10530936e-01, 2.19498828e-01, 2.27998286e-01, 2.36098647e-01, 2.43854254e-01, 2.51308768e-01, 2.58497864e-01, 2.65450924e-01, 2.72192806e-01, 2.78744399e-01, 2.85123795e-01, 2.91346460e-01, 2.97426044e-01, 3.03374379e-01, 3.09202045e-01, 3.14918369e-01, 3.20531696e-01, 3.26049506e-01, 3.31478625e-01, 3.36825191e-01, 3.42094779e-01, 3.47292482e-01, 3.52423042e-01, 3.57490718e-01, 3.62499535e-01, 3.67453157e-01, 3.72355014e-01, 3.77208292e-01, 3.82015973e-01, 3.86780887e-01, 3.91505628e-01, 3.96192669e-01, 4.00844365e-01, 4.05462920e-01, 4.10050421e-01, 4.14608865e-01, 4.19140160e-01, 4.23646122e-01, 4.28128510e-01, 4.32588934e-01, 4.37029063e-01, 4.41450417e-01, 4.45854485e-01, 4.50242727e-01, 4.54616576e-01, 4.58977371e-01, 4.63326483e-01, 4.67665165e-01, 4.71994757e-01, 4.76316481e-01, 4.80631619e-01, 4.84941333e-01, 4.89246904e-01, 4.93549466e-01, 4.97850269e-01, 5.02150475e-01, 5.06451249e-01, 5.10753810e-01, 5.15059411e-01, 5.19369125e-01, 5.23684263e-01, 5.28005957e-01, 5.32335579e-01, 5.36674261e-01, 5.41023373e-01, 5.45384168e-01, 5.49758017e-01, 5.54146230e-01, 5.58550298e-01, 5.62971651e-01, 5.67411780e-01, 5.71872234e-01, 5.76354622e-01, 5.80860555e-01, 5.85391879e-01, 5.89950323e-01, 5.94537794e-01, 5.99156379e-01, 6.03808045e-01, 6.08495116e-01, 6.13219857e-01, 6.17984771e-01, 6.22792422e-01, 6.27645730e-01, 6.32547557e-01, 6.37501180e-01, 6.42509996e-01, 6.47577702e-01, 6.52708232e-01, 6.57905936e-01, 6.63175523e-01, 6.68522059e-01, 6.73951208e-01, 6.79469048e-01, 6.85082376e-01, 6.90798640e-01, 6.96626305e-01, 7.02574670e-01, 7.08654224e-01, 7.14876949e-01, 7.21256315e-01, 7.27807879e-01, 7.34549760e-01, 7.41502821e-01, 7.48691916e-01, 7.56146430e-01, 7.63902068e-01, 7.72002398e-01, 7.80501842e-01, 7.89469778e-01, 7.98996329e-01, 8.09203147e-01, 8.20259928e-01, 8.32416176e-01, 8.46063911e-01, 8.61882984e-01, 8.81251752e-01, 9.07943725e-01, 1.0e+00};

fn preGeneratePercentileTable() void {
	const randomNumbers = 4096;
	const positions = 4096;
	const totalValues = randomNumbers*positions;
	const values = randomNumbers;
	var amount1D: [values + 1]u128 = undefined;
	@memset(&amount1D, 0);
	for(0..randomNumbers) |a| {
		for(0..randomNumbers) |b| {
			for(0..positions + 1) |x| {
				const val = x*(2*a + 1) + (positions - x)*(2*b + 1);
				amount1D[(val*values)/totalValues/2] += 1;
			}
		}
	}
	var amount2D: [values + 1]u128 = undefined;
	@memset(&amount2D, 0);
	for(0..randomNumbers) |a| {
		for(0..randomNumbers) |b| {
			for(0..positions + 1) |x| {
				const val = x*(2*a + 1) + (positions - x)*(2*b + 1);
				amount2D[(val*values)/totalValues/2] += amount1D[a]*amount1D[b];
			}
		}
	}
	var samples: u128 = 0;
	for(&amount2D) |val| {
		samples = std.math.add(u128, samples, val) catch @panic("Number too big");
	}
	std.log.info("{}", .{samples});

	var percentiles: [128]f32 = undefined;
	var current: u128 = 0;
	var i: usize = 0;
	for(&percentiles, 0..) |*_percentile, j| {
		const goal = j*samples/(percentiles.len - 1);
		while(current + amount2D[i] < goal) {
			current += amount2D[i];
			i += 1;
		}
		const diff = goal - current;
		_percentile.* = (@as(f32, @floatFromInt(i)) + @as(f32, @floatFromInt(diff))/@as(f32, @floatFromInt(amount2D[i])))/randomNumbers;
	}

	for(&percentiles) |_percentile| {
		std.log.info("{}", .{_percentile});
	}
}

pub fn percentile(ratio: f32) f32 {
	std.debug.assert(ratio >= 0);
	const scaledToList = ratio*@as(f32, @floatFromInt(percentileTable.len));
	const index: u32 = @intFromFloat(scaledToList);
	if(index >= percentileTable.len - 1) return 1;
	const offset = (scaledToList - @as(f32, @floatFromInt(index)));
	return (1 - offset)*percentileTable[index] + offset*percentileTable[index + 1];
}
