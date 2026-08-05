//--------------------------------------------------------------
//	Object Constructor for the distance object
//--------------------------------------------------------------
function Distobj(dDist, dBearing12, dBearing21){
	this.length = 3;
	this.DistanceKm = dDist;
	this.Bearing12 = dBearing12;
	this.Bearing21 = dBearing21;
  return this;
}


//--------------------------------------------------------------
//	Return the distance in Km and bearing in degrees between
//	two lats and longs in degrees
//--------------------------------------------------------------
function dist(lat1, long1, lat2, long2){
	var		rlat1;
	var		rlong1;
	var		rlat2;
	var		rlong2;
	var		latdiff;
	var		longdiff;
	var		oDist;
	var		latavr;
	var		c1;
	var		sinlatavr;
	var		am;
	var		bearingmid;
	var		bearingdiff;

	var		distancekm;
	var 	bearing12;
	var		bearing21;

	rlat1 = torad(lat1);
	rlong1 = torad(long1);
	rlat2 = torad(lat2);
	rlong2 = torad(long2);

	latdiff = rlat1 - rlat2;
  if (latdiff == 0.0){
    latdiff = 1e-8;
  }
	longdiff = rlong1 - rlong2;
  if (longdiff == 0.0){
    longdiff = 1e-8;
  }
	latavr = (rlat1 + rlat2) / 2;
	sinlatavr = Math.sin(latavr);

	//	1 - eccentricity**2 * sin(avlat)**2
	c1 = 1 - (0.00669454 * sinlatavr * sinlatavr);
	am = Math.sqrt(c1) / 30.9221917;
	bearingmid = Math.atan(longdiff * Math.cos(latavr) * c1 /
	                       (0.99330546 * latdiff));
	bearingmid = bearingmid < 0.0 ? -bearingmid : bearingmid;
	bearingdiff = longdiff * Math.sin(latavr);

	bearing12 = bearingmid - bearingdiff / 2;
	if (latdiff >= 0.0){
		if (longdiff < 0.0){
			bearing12 += Math.PI;
		} else {
			bearing12 = Math.PI - bearing12 - bearingdiff;
		}
	} else if (longdiff <= 0.0){
		bearing12 = 2.0 * Math.PI - bearing12 - bearingdiff;
	}

  if (bearing12 > 2.0 * Math.PI){
    bearing12 -= 2.0 * Math.PI;
  }

	bearing21 = bearing12 + bearingdiff + Math.PI;
	if (bearing21 > 2.0 * Math.PI){
		bearing21 -= 2.0 * Math.PI;
	}

	distancekm = (longdiff * Math.cos(latavr)) /
		        (am * Math.sin(bearingmid) * 0.0048481368);
	distancekm = (distancekm < 0.0) ? -distancekm : distancekm;

	return(new Distobj(distancekm, todeg(bearing12), todeg(bearing21)));
}


//-------------------------------------------------------------------
//  create an elevation object, consisting of the opposite elevations
//	and the actual path distance between the two.
//-------------------------------------------------------------------
function elevobj(felev12, felev21)
{
  this.length = 2;
  this.elev12 = felev12;
  this.elev21 = felev21;
}


//------------------------------------------------------------------
//  Elevation angles between two antennas.  Heights and distances
//  all in km.	
//------------------------------------------------------------------
function elev(anthtkm1, anthtkm2, distkm)
{
  var     temp1;
  var     temp2;

  //  temp1 = D/2RK, K = 4/3
  temp1 = distkm / 16999.50667;
  temp2 = Math.atan((anthtkm2 - anthtkm1) /
                    ((16999.50667 + anthtkm1 + anthtkm2) * Math.tan(temp1)));
  return (new elevobj(todeg(temp2 - temp1), todeg(-temp2 - temp1)));
}


function calcdist()
{
  var   lata;
  var   latb;
  var   longa;
  var   longb;
  var   nInd;
  var   oDist;
  var   oElev;
  var   ht;
  var   hta;
  var   htb;

	var		R	= 6374.815;		//	Radius of the earth (km)

  var		Ra;
  var		Rb;
  var		pDist;

  if (!checktext(document.forms["fDist"].latdega.value,
                   -90.0, 90.0, "Lat deg a")) return false;
  if (! checktext(document.forms["fDist"].latmina.value,
                   0.0, 59.99, "Lat min a")) return false;
  if (! checktext(document.forms["fDist"].latseca.value,
                   0.0, 59.99, "Lat sec a")) return false;
  if (! checktext(document.forms["fDist"].latdegb.value,
                   -90.0, 90.0, "Lat deg b")) return false;
  if (! checktext(document.forms["fDist"].latminb.value,
                   0.0, 59.99, "Lat min b")) return false;
  if (! checktext(document.forms["fDist"].latsecb.value,
                   0.0, 59.99, "Lat sec b")) return false;

  if (! checktext(document.forms["fDist"].londega.value,
                   -180.0, 180.0, "long deg a")) return false;
  if (! checktext(document.forms["fDist"].lonmina.value,
                   0.0, 59.99, "long min a")) return false;
  if (! checktext(document.forms["fDist"].lonseca.value,
                   0.0, 59.99, "long sec a")) return false;
  if (! checktext(document.forms["fDist"].londegb.value,
                   -180.0, 180.0, "long deg b")) return false;
  if (! checktext(document.forms["fDist"].lonminb.value,
                   0.0, 59.99, "long min b")) return false;
  if (! checktext(document.forms["fDist"].lonsecb.value,
                   0.0, 59.99, "long sec b")) return false;

  //  save the sign and calculate the full latitude in degress, then apply
  //  the sign

  lata = degval(document.forms["fDist"].latdega.value,
                document.forms["fDist"].latmina.value,
                document.forms["fDist"].latseca.value);
  latb = degval(document.forms["fDist"].latdegb.value,
                document.forms["fDist"].latminb.value,
                document.forms["fDist"].latsecb.value);

  longa = degval(document.forms["fDist"].londega.value,
                 document.forms["fDist"].lonmina.value,
                 document.forms["fDist"].lonseca.value);
  longb = degval(document.forms["fDist"].londegb.value,
                 document.forms["fDist"].lonminb.value,
                 document.forms["fDist"].lonsecb.value);

  oDist = dist(lata, longa, latb, longb);

  document.forms["fDist"].tDist.value = oDist.DistanceKm.toFixed(3);
  document.forms["fDist"].tBearAB.value = oDist.Bearing12.toFixed(1);
  document.forms["fDist"].tBearBA.value = oDist.Bearing21.toFixed(1);

  hta = document.forms["fDist"].hta.value / 1000.0;
  hta += document.forms["fDist"].ahta.value / 1000.0;
  htb = document.forms["fDist"].htb.value / 1000.0;
  htb += document.forms["fDist"].ahtb.value / 1000.0;

  oElev = elev(hta, htb, oDist.DistanceKm);

  //  Now fill in the elevation angles
  document.forms["fDist"].tElevAB.value = oElev.elev12.toFixed(2);
  document.forms["fDist"].tElevBA.value = oElev.elev21.toFixed(2);
  
  //	Calculate the actual path distance from the triangle formed by
  //	the radius of the earth to the antennas, the angular separation
  //	at the centre of the earth, and the path.
  Ra = R + hta;
  Rb = R + htb;
  pDist = Math.sqrt(Math.pow(Ra, 2.0) + Math.pow(Rb, 2.0) - 
          2.0 * Ra * Rb * Math.cos(oDist.DistanceKm / R));
	document.forms["fDist"].pDist.value = pDist.toFixed(3);

	//--------------- Superceded by the above ------------------------
  //	Using the elevation angles we can calculate the actual path
  //	distance.  This is the hypotenuse of the triangle formed when
  //	the elevation angles are non-zero.  This is really only relevant
  //	when the sites are close, and altitudes differ greatly.
  //document.forms["fDist"].pDist.value = (oDist.DistanceKm /
  //     Math.cos(oElev.elev12 * Math.PI / 180.0)).toFixed(2);
}

