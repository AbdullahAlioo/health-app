# AI Health Monitor Data Generation Prompt

## Objective
Generate realistic health monitoring data every 30 seconds and print it to the terminal. The data should be calculated accurately based on sensor inputs and user activity patterns.

## Output Format
Print JSON data to terminal every 30 seconds in this exact format:
```json
{
  "heartRate": 72,
  "steps": 1500,
  "spo2": 98,
  "calories": 120,
  "sleep": 6.5,
  "recovery": 85,
  "stress": 30,
  "rhr": 65,
  "hrv": 45,
  "bodyTemperature": 36.5,
  "breathingRate": 16
}
```

## Requirements

### 1. Data Collection (Every 30 seconds)
Monitor and calculate the following metrics:

#### Heart Rate (heartRate)
- Current heart rate in BPM (beats per minute)
- Analyze heart rate points to detect patterns
- Make decisions based on heart rate variability
- Normal range: 60-100 BPM (resting), 100-170 BPM (active)

#### Steps (steps)
- Total step count since monitoring started
- Use accelerometer data to detect movement
- Increment based on detected step patterns

#### SpO2 (spo2)
- Blood oxygen saturation percentage
- Normal range: 95-100%
- Calculate from sensor readings

#### Calories (calories)
- Estimated calories burned
- Calculate based on: steps, heart rate, duration, and user profile
- Update continuously

#### Sleep Hours (sleep)
- Total sleep duration in hours (decimal format)
- Detect sleep state (see Resting Heart Rate section)

#### Recovery Score (recovery)
- Optional for now (you mentioned excluding this)
- Can be calculated later based on sleep quality and HRV

#### Stress Level (stress)
- Stress score from 0-100
- Calculate based on:
  - Heart rate variability (HRV)
  - Elevated heart rate
  - Breathing rate
- Lower is better

#### Resting Heart Rate (rhr)
- **Critical Feature**: Detect when user has NO movement or LITTLE movement for 30 minutes
- If movement is minimal/absent for 30 min → User is sleeping
- During sleep detection:
  - Calculate average heart rate during this period
  - This becomes the Resting Heart Rate (RHR)
  - Normal RHR: 60-100 BPM (lower is generally better for fitness)

#### Heart Rate Variability (hrv)
- Variation in time between heartbeats (in milliseconds)
- Higher HRV generally indicates better cardiovascular fitness
- Normal range: 20-200 ms
- Calculate from heart rate data points

#### Body Temperature (bodyTemperature)
- Core body temperature in Celsius
- Normal range: 36.1-37.2°C

#### Breathing Rate (breathingRate)
- Breaths per minute
- Normal range: 12-20 breaths/min
- Can be estimated from heart rate patterns or dedicated sensor

## Detection Logic

### Sleep Detection Algorithm
```
1. Monitor accelerometer data continuously
2. Track movement in 30-minute windows
3. If movement count < threshold for 30 minutes:
   - Set sleep state = TRUE
   - Start calculating RHR from current heart rate
   - Increment sleep hours
4. If movement detected after sleep:
   - Set sleep state = FALSE
   - Finalize RHR calculation
```

### Heart Rate Analysis
```
1. Collect heart rate points every measurement cycle
2. Analyze patterns:
   - Sudden spikes → Possible stress or activity
   - Consistently low + no movement → Sleep detected
   - High variability → Good cardiovascular health
3. Make decision based on:
   - Is user sleeping? (RHR detection)
   - Is user stressed? (elevated HR + low HRV)
   - Is user active? (high HR + high step count)
```

### Resting Heart Rate (RHR) Detection
```
1. Monitor movement sensor continuously
2. If no/little movement for 30 minutes:
   - User is likely sleeping
   - Calculate average heart rate during this period
   - This is the Resting Heart Rate
3. Update RHR value in output
```

## Implementation Steps (For AI)

### Step 1: Initialize Variables
- Set up counters for steps, calories, sleep time
- Initialize heart rate buffers for analysis
- Create movement detection window (30 min)

### Step 2: Every 30 Seconds Loop
```
1. Read current sensor values (heart rate, movement, temperature)
2. Calculate SpO2 from sensor
3. Detect steps from accelerometer
4. Check movement in last 30 minutes for sleep detection
5. If sleeping → calculate RHR
6. Calculate HRV from heart rate variability
7. Estimate stress from HR + HRV + breathing
8. Calculate calories from activity
9. Print JSON to terminal
10. Wait 30 seconds
11. Repeat
```

### Step 3: Print to Terminal
- Use `print()` or `console.log()` depending on language
- Format as valid JSON
- Include timestamp if needed for debugging

## Realistic Value Ranges

| Metric | Resting | Light Activity | Moderate Activity | Sleep |
|--------|---------|----------------|-------------------|-------|
| Heart Rate | 60-100 | 90-120 | 120-150 | 40-60 |
| Steps/30s | 0-50 | 50-200 | 200-500 | 0-5 |
| SpO2 | 95-100 | 95-100 | 95-99 | 95-100 |
| Stress | 10-30 | 20-40 | 30-50 | 5-15 |
| HRV | 40-60 | 30-50 | 20-40 | 50-80 |

## Example Output Timeline

**Minute 0 (User active):**
```json
{
  "heartRate": 95,
  "steps": 150,
  "spo2": 98,
  "calories": 15,
  "sleep": 0,
  "recovery": 75,
  "stress": 35,
  "rhr": 65,
  "hrv": 42,
  "bodyTemperature": 36.8,
  "breathingRate": 18
}
```

**Minute 30 (User still active):**
```json
{
  "heartRate": 88,
  "steps": 1500,
  "spo2": 98,
  "calories": 120,
  "sleep": 0,
  "recovery": 75,
  "stress": 30,
  "rhr": 65,
  "hrv": 45,
  "bodyTemperature": 36.7,
  "breathingRate": 16
}
```

**Minute 60 (User sleeping - no movement for 30+ min):**
```json
{
  "heartRate": 58,
  "steps": 1503,
  "spo2": 97,
  "calories": 125,
  "sleep": 0.5,
  "recovery": 80,
  "stress": 10,
  "rhr": 58,
  "hrv": 65,
  "bodyTemperature": 36.3,
  "breathingRate": 14
}
```

## Important Notes

1. **Step-by-step approach**: Focus on one metric at a time, don't try to implement everything at once
2. **Start simple**: Begin with basic heart rate and step counting, then add complexity
3. **Terminal output only**: Don't send data via BLE or network - just print to console
4. **30-second intervals**: Use a timer/sleep function to maintain consistent intervals
5. **RHR is critical**: The 30-minute no-movement detection for sleep/RHR is a key feature
6. **Accuracy matters**: All calculations except recovery should be as accurate as possible
7. **Realistic data**: Values should make physiological sense and correlate with each other

## Upgrade Path (Future)
- Add data persistence (save to file/database)
- Implement recovery score calculation
- Add BLE transmission capability
- Create historical data analysis
- Add AI predictions based on patterns
