/* burn.c -- spin load to occupy exactly one CPU (SMT calibration).
 * Build: gcc -O2 -o burn burn.c   Usage: taskset -c <cpu> ./burn */
int main(void)
{
	volatile unsigned long x = 0;
	for (;;)
		x++;
	return 0;
}
