module nn.Testing;

import tango.math.Math;

import algo.NNIndex;
import dataset.Dataset;
import util.Logger;
import util.Profile;
import console.report.Report;
import algo.dist;
import util.Utils;


const float SEARCH_EPS = 0.001;

template search(bool withOutput) {


int countCorrectMatches(int[] neighbors, int[] groundTruth)
{
	int n = neighbors.length;
	
	int count = 0;
	foreach(m;neighbors) {
		for (int i=0;i<n;++i) {
			if (groundTruth[i]==m) {
				count++;
				break;
			}
		}
	}
	return count;
}


float computeDistanceRaport(float[] target, int[] neighbors, int[] groundTruth)
{
	int n = neighbors.length;
	
	float ret = 0;
	foreach(i,m;neighbors) {
		float den = squaredDist(target,vecs[groundTruth[i]]);
		float num = squaredDist(target,vecs[m]);
		
		if (den==0 && num==0) {
			ret += 1;
		} else {
			ret += num/den;
		}
	}
	
	return ret;
}

float search(int checks, out float time) 
{
	if (matches[0].length<nn) {
		throw new FLANNException("Ground truth is not computed for as many neighbors as requested");
	}
	
	int correct;
	float distR;
	time = profile( {
		correct = 0;
		distR = 0;
		for (int i = 0; i < testData.rows; i++) {
			auto target = testData.vecs[i];
			resultSet.init(target);
			index.findNeighbors(resultSet,target, checks);			
			int[] neighbors = resultSet.getNeighbors();
			neighbors = neighbors[skipMatches..$];
					
			correct += countCorrectMatches(neighbors,matches[i]);
			distR += computeDistanceRaport(target,neighbors,matches[i]);
		}
	},0.2);
	
	
	float performance = cast(float)correct/(nn*testData.rows);
	
	static if (withOutput) {
		logger.info(sprint("{,8}{,10:d2}{,12:d3}{,12:d3}{,12:d3}",
				checks, performance,
				time, 1000.0 * time / testData.rows, distR/testData.rows));
	}
	
	return performance;
}
}



float testNNIndex(T, bool withOutput, bool withReporting)
				(NNIndex index, Dataset!(T) inputData, Dataset!(float) testData, int[][] matches, int checks, int nn = 1, uint skipMatches = 0)
{
	T[][] vecs = inputData.vecs;
	
	static if (withOutput)
		logger.info("Searching... ");
	
	ResultSet resultSet = new ResultSet(nn+skipMatches);
	
	mixin search!(withOutput);
	
	static if (withOutput) {		
		logger.info("  Nodes  Precision(%)   Time(s)   Time/vec(ms)  Mean dist");
		logger.info("---------------------------------------------------------");
	}
	
	float time;
	float precision = search(checks,time);

	static if (withReporting) {
		report("checks", checks)
			("match",cast(double)precision)
			("search_time", cast(double)time).flush;
	}

	return time;
}


float testNNIndexPrecision(T, bool withOutput, bool withReporting)
						(NNIndex index,Dataset!(T) inputData, Dataset!(float) testData, int[][] matches, float precision, out int checks, int nn = 1, uint skipMatches = 0)
{	
	T[][] vecs = inputData.vecs;
	
	static if (withOutput) {
		logger.info("  Nodes  Precision(%)   Time(s)   Time/vec(ms)  Mean dist");
		logger.info("---------------------------------------------------------");
	}
	
	ResultSet resultSet = new ResultSet(nn+skipMatches);
	
	mixin search!(withOutput);

	int c2 = 1;
	float p2;
	
	int c1;
	float p1;
	
	float time;
	
	p2 = search(c2,time);
	
	if (p2>precision) {
		static if (withOutput) logger.info("Got as close as I can");
		checks = c2;
		return time;
	}

	while (p2<precision) {
		c1 = c2;
		p1 = p2;
		c2 *=2;
		p2 = search(c2,time);
	}	
	
	// TODO: detect infinite loop here
	int cx;
	float realPrecision;
	if (abs(p2-precision)>SEARCH_EPS) {
		static if (withOutput) logger.info("Start linear estimation");
		// after we got to values in the vecinity of the desired precision
		// use linear approximation get a better estimation
			
		cx = (c1+c2)/2;
		realPrecision = search(cx,time);
		while (abs(realPrecision-precision)>SEARCH_EPS) {
			
			if (realPrecision<precision) {
				c1 = cx;
			}
			else {
				c2 = cx;
			}
			cx = (c1+c2)/2;
			if (cx==c1) {
				static if (withOutput) logger.info("Got as close as I can");
				break;
			}
			realPrecision = search(cx,time);
		}
		
		c2 = cx;
		p2 = realPrecision;
		
	} else {
		static if (withOutput) logger.info("No need for linear estimation");
		cx = c2;
		realPrecision = p2;
	}
	
	static if (withReporting) {
		report("checks", cx)
			("match", cast(double)realPrecision)
			("search_time", cast(double)time).flush;
	}
	
	checks = cx;
	return time;
}


float testNNIndexPrecisions(T, bool withOutput, bool withReporting)
						(NNIndex index,Dataset!(T) inputData, Dataset!(float) testData,int[][] matches, float[] precisions, int nn = 1, uint skipMatches = 0, float maxTime = 0)
{	
	// make sure precisions array is sorted
	precisions.sort;
	int pindex = 0;
	float precision = precisions[pindex];
	
	T[][] vecs = inputData.vecs;
	
	static if (withOutput) {
		logger.info("  Nodes  Precision(%)   Time(s)   Time/vec(ms)  Mean dist");
		logger.info("---------------------------------------------------------");
	}
	
	ResultSet resultSet = new ResultSet(nn+skipMatches);
	
	mixin search!(withOutput);

	int c2 = 1;
	float p2;
	
	int c1;
	float p1;
	
	float time;
	
	p2 = search(c2,time);	
	
	static if (withReporting) {
		report("checks", c2)
			("match", cast(double)p2)
			("search_time", cast(double)time);
	}
	
	
	// if precision for 1 run down the tree is already
	// better then some of the requested precisions, then
	// skip those
	while (precisions[pindex]<p2 && pindex<precisions.length) {
		pindex++;
	}
	
	if (pindex==precisions.length) {
		static if (withOutput) logger.info("Got as close as I can");
		report.flush();
		return time;
	}
	
	
	
	for (int i=pindex;i<precisions.length;++i) {
	
		precision = precisions[i];
		while (p2<precision) {
			c1 = c2;
			p1 = p2;
			c2 *=2;
			p2 = search(c2,time);
			if (maxTime> 0 && time > maxTime && p2<precision) return time;
		}
		
		int cx;
		float realPrecision;
		if (abs(p2-precision)>SEARCH_EPS) {
			static if (withOutput) logger.info("Start linear estimation");
			// after we got to values in the vecinity of the desired precision
			// use linear approximation get a better estimation
				
			cx = (c1+c2)/2;
			realPrecision = search(cx,time);
			while (abs(realPrecision-precision)>SEARCH_EPS) {
				
				if (realPrecision<precision) {
					c1 = cx;
				}
				else {
					c2 = cx;
				}
				cx = (c1+c2)/2;
				if (cx==c1) {
					static if (withOutput) logger.info("Got as close as I can");
					break;
				}
				realPrecision = search(cx,time);
			}
			
			c2 = cx;
			p2 = realPrecision;
			
		} else {
			static if (withOutput) logger.info("No need for linear estimation");
			cx = c2;
			realPrecision = p2;
		}
		
		static if (withReporting) {
			report("checks", cx)
				("match", cast(double)realPrecision)
				("search_time", cast(double)time).flush;
		}
	}
	return time;
}



float testNNIndexPrecisionAlt(T, bool withOutput, bool withReporting)
						(NNIndex index, Dataset!(T) inputData, Dataset!(float) testData, int[][] matches, float precision, out int checks, int nn = 1, uint skipMatches = 0)
{
	T[][] vecs = inputData.vecs;

	static if (withOutput) {
		logger.info("Searching... ");
		logger.info("  Nodes  Precision(%)   Time(s)   Time/vec(ms)  Mean dist");
		logger.info("---------------------------------------------------------");
 	}

	ResultSet resultSet = new ResultSet(nn+skipMatches);
	
	mixin search!(withOutput);

	int estimate(int[] checks, float[] precision, int count, float desiredPrecision) {
		
		float[2][2] A;
		float[2] b;
		
		b[] = 0;
		A[0][] = 0;
		A[1][] = 0;
		
		for (int i=0;i<count;++i) {
			float c = log(checks[i]);
			float p = 1 - precision[i];
			A[1][1] += c*c;
			A[0][1] -= c;
			b[0] += c*p;
			b[1] += p;
		}
		A[1][0] = A[0][1];
		A[0][0] = count;
		
		float d = A[0][0]*A[1][1]-A[0][1]*A[1][0];
		
		float x[2];
		x[0] = (A[0][0]*b[0]+A[0][1]*b[1])/d;
		x[1] = (A[1][0]*b[0]+A[1][1]*b[1])/d;
		
		float cx = exp((1-desiredPrecision-x[1])/x[0]);
		
		return rndint(cx);
	}

	
	const int MAX_CHECKS = 20;
	const float VECINITY_INTERVAL = 2;
	float SLOPE_EPS = tan(5*PI/180);
	
	int[MAX_CHECKS] c;
	float[MAX_CHECKS] p;	
	float time;
	int count;
	
	// get two samples of numbet_of_checks-precision dependencies
	count = 0;
	c[count] = 1;	
	p[count] = search(c[count],time);
	count++;
	
	c[count] = 5;	
	p[count] = search(c[count],time);
	count++;
	
	c[count] = 	estimate(c,p,count, 60);
	p[count] = search(c[count],time);
	count++;
	
	c[count] = 	estimate(c,p,count, 70);
	p[count] = search(c[count],time);
	count++;
	
	c[count] = 	estimate(c,p,count, 80);
	p[count] = search(c[count],time);
	count++;
	
	c[count] = 	estimate(c,p,count, precision);
	p[count] = search(c[count],time);
	count++;
	
	// use least square to estimate checks no. to obtain something close to
	// desired precision
	
	float m1 = (p[count-2]-p[count-3])/(c[count-2]-c[count-3]);
	float m2 = (p[count-1]-p[count-2])/(c[count-1]-c[count-2]);	
	float alpha = abs((m1-m2)/(1+m1*m2));
 	static if (withOutput) logger.info(sprint("m1={}, m2={}, alpha = {}",m1,m2,alpha));	
	
	while (alpha>SLOPE_EPS && abs(p[count-1]-precision)>SEARCH_EPS) {
		c[count] = estimate(c,p,count, precision);
		p[count] = search(c[count],time);
		if (abs(p[count]-p[count-1])<0.001) {
			break;
		}
		count++;
		m1 = m2;
		m2 = (p[count-1]-p[count-2])/(c[count-1]-c[count-2]);
		alpha = abs((m1-m2)/(1+m1*m2));
	 	static if (withOutput) logger.info(sprint("m1={}, m2={}, alpha = {}",m1,m2,alpha));	
	}
	
	int cx;
	float realPrecision;
	if (abs(p[count-1]-precision)>SEARCH_EPS) {
		static if (withOutput) logger.info("Start linear estimation");
		// after we got to values in the vecibity of the desired precision
		// use linear approximation get a better estimation
		int c1 = c[count-2], c2 = c[count-1];
		float p1 = p[count-2], p2 = p[count - 1];
			
		cx = rndint(c1+(precision-p1)*(c2-c1)/(p2-p1));
		realPrecision = search(cx,time);
		while (abs(realPrecision-precision)>SEARCH_EPS) {
			if (p2!=realPrecision) {
				c1 = c2; p1 = p2;
			}
			c2 = cx; p2 = realPrecision;
			cx = rndint(c1+(precision-p1)*(c2-c1)/(p2-p1));
			if (c2==cx) {
				cx += precision>realPrecision?1:-1;
			}
			if (cx==c1) {
				static if (withOutput) logger.info("Got as close as I can");
				break;
			}
			realPrecision = search(cx,time);
		}
		
	} else {
		static if (withOutput) logger.info("No need for linear estimation");
		cx = c[count-1];
		realPrecision = p[count-1];
	}
	
	static if (withReporting) {
		report("checks", cx)
			("match", cast(double)realPrecision)
			("search_time", cast(double)time).flush;
	}

	checks = cx;
	return time;
}
