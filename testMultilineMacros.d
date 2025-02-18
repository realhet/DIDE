#include <stdio.h>
#define MACRO(num, str) {printf("%d", num);\
printf(" is");\
printf(" %s number", str);\
printf("\n");}
#define MACRO2(num, str)\
	printf("%d", num);\
	printf(" is");\
	printf(" %s number", str);\
	printf("\n"); 
#define MACRO2(num, str) printf("%d", num);

#if a
#undef b
#akarmi x

#! fjdksa

int main(void) 
{
	int num; 
	
	printf("Enter a number: "); 
	scanf("%d", &num); 
	
	if(num & 1)
	MACRO(num, "Odd"); 
	else
	MACRO(num, "Even"); 
	
	return 0; 
} 