//--------------------------------------------------------------
// 	Return the angle in radians given an angle in degrees.
//--------------------------------------------------------------
function torad(angleindeg){
	return (angleindeg * 0.0174532925199);
}


//--------------------------------------------------------------
// 	Return the angle in degrees given an angle in radians.
//--------------------------------------------------------------
function todeg(angleinrad){
	return (angleinrad * 57.2957795132);
}


//--------------------------------------------------------------
// 	Make an angle in degrees out of its component degrees,
//	minutes and seconds.
//--------------------------------------------------------------
function makedeg(degrees, minutes, seconds){
	if (degrees < 0){
		return(degrees - (minutes / 60) - (seconds / 3600));
	} else {
		return(degrees + (minutes / 60) + (seconds / 3600));
	}
}


//--------------------------------------------------------------
//  check that a value is within range.
//--------------------------------------------------------------
function checktext(fVal, fLow, fHi, cMess)
{
  if (fVal < fLow || fVal > fHi){
    alert(cMess + " is out of range.");
    return false;
  }
  return true;
}


//-----------------------------------------------------------------
//  Return the floating point degrees from degrees minutes and secs
//-----------------------------------------------------------------
function degval(fdeg, fmin, fsec)
{
  var     nInd;
  var     deg;

  nInd = fdeg >= 0 ? 1 : -1;
  deg  = Math.abs(fdeg) +
         fmin / 60.0 +
         fsec / 3600.0;
  return deg * nInd;
}

//------------------------------------------------------------------------
//	Break floating point degrees into degrees, minutes, seconds and sense.
//	This is a constructor and must be called with the 'new' keyword.
//------------------------------------------------------------------------
function tMakeDegree(dDegrees)
{
	var nSign = (dDegrees < 0) ? -1 : +1;
	var dRest;
	
	dDegrees *= nSign;		//	Take the absolute value.
	this.Degrees = Math.floor(dDegrees);
	dDegrees = (dDegrees - this.Degrees) * 60.0;
	this.Minutes = Math.floor(dDegrees);
	//	Multiply by 100 to round.
	dDegrees = Math.round((dDegrees - this.Minutes) * 6000.0);
	this.Seconds = Math.floor(dDegrees / 100);
	this.Hundredths = Math.round(((dDegrees / 100) - this.Seconds) * 100);
	this.Sense = nSign;
	this.Length = 5;
	
	return this;
}


//------------------------------------------------------------------------
//	Latitude and Longitude creators.
//------------------------------------------------------------------------
function tMakeLat(dDegrees)
{
	var oLat = new tMakeDegree(dDegrees);
	
	if (oLat.Sense < 0){
		oLat.Sense = "S";
	} else {
		oLat.Sense = "N";
	}
	
	return oLat;
}


//------------------------------------------
function tMakeLong(dDegrees)
{
	var oLong = new tMakeDegree(dDegrees);
	
	if (oLong.Sense < 0){
		oLong.Sense = "E";		//	Note that FCSA is the reverse of normal
	} else {
		oLong.Sense = "W";
	}
	
	return oLong;
}


//--------------------------------------------------------------------------
//	Formating the lat and long.
//--------------------------------------------------------------------------
function numtostring(dNum, nLength)
{
	var outstr = new String(dNum.toString());
	
	if (outstr.length < nLength){
		outstr = "0000000000".substring(0, nLength - outstr.length) + outstr;
	}
	
	return outstr;
}


//-------------------------------------------------------------------------
//  Display a Latitude that comes in in integer seconds * 100
//-------------------------------------------------------------------------
function dispLat(nDegrees)
{
	var oDeg = new tMakeLat(nDegrees / 360000.0);
	var sOutStr;
	
	sOutStr = numtostring(oDeg.Degrees, 2) + "-" +
						numtostring(oDeg.Minutes, 2) + "-" +
						numtostring(oDeg.Seconds, 2) + "." +
						numtostring(oDeg.Hundredths, 2) + " " +
						oDeg.Sense;
	return sOutStr;
}


//-------------------------------------------------------------------------
//  Display a Longitude that comes in in integer seconds * 100
//-------------------------------------------------------------------------
function dispLong(nDegrees)
{
	var oDeg = new tMakeLong(nDegrees / 360000.0);
	var sOutStr;
	
	sOutStr = numtostring(oDeg.Degrees, 3) + "-" +
						numtostring(oDeg.Minutes, 2) + "-" +
						numtostring(oDeg.Seconds, 2) + "." +
						numtostring(oDeg.Hundredths, 2) + " " +
						oDeg.Sense;
	return sOutStr;
}


//------------------------------------------------------------------------
//	Convert float Degrees to integer seconds * 100
//------------------------------------------------------------------------
function toSec100(dDeg)
{
	return Math.round(dDeg * 360000);
}


//------------------------------------------------------------------------
//	Parse a lat/long in the form [D]DD-MM-SS.HHO into a floating point 
//	number.  Throws an error if it finds one.
//------------------------------------------------------------------------
function parseLL(cLat, nMax, cSenses)
//	Return a latitude/longitude in degrees from a [D]DD-MM-SS.HHN string.
{
	var pattern = /^(\d{1,3})-(\d{1,2})(-[\d\.]{0,5})?([NnSsEeWw]?)$/i;
	var retval;
	var dDeg;
	var	dMin;
	var	dSec;
	var dSense;
	
	try{
		if (pattern.exec(cLat) == null){
			retval = "No Match";
		} else {
			dDeg = parseInt(RegExp.$1, 10);
			dMin = parseInt(RegExp.$2, 10);
			dSec = parseInt(RegExp.$3, 10);
			dSense = RegExp.$4;
			
			// The seconds will have the preceeding - as part of it. Remove this.
			if (isNaN(dSec)){
				dSec = 0;
			} else {
				dSec = -dSec;
			}
			if (isNaN(dMin)){
				dMin = 0.0;
			}
			if (isNaN(dDeg)){
				dDeg = 0.0;
			}
			
			if (dSense == "" || dSense == null){
				dSense = "N";
			} else {
				dSense = dSense.toUpperCase();
				if (cSenses.indexOf(dSense) == -1){
					throw "Sense must be " + cSenses.charAt(0) + " or " + cSenses.charAt(1);
				}
			}
			
			if (dSec >= 60.0){
				throw "60 seconds or more.";
			}
			
			if (dMin >= 60.0){
				throw "60 minutes or more.";
			}
			
			if (dDeg > nMax){
				throw "More than " + nMax + " degrees.";
			}
			
			retval = dDeg + (dMin / 60.0) + (dSec / 3600.0);
			if (dSense == "S" || dSense == "E"){
				retval = -retval;
			}
		}
	} catch (e) {
		retval = "Error: " + e;
	}
	
	return retval;
}


//-----------------------------------------------------------------------------
//	Check a latitude for validity.  Input is a textbox that should contain it.
//	The output latitude is stored in the textbox as the "degrees" property.
//-----------------------------------------------------------------------------
function latcheck(oCont)
//	check a latitude on exit from its text box
{
	var		dLat;
	
	if (oCont.value == ""){
		// Make sure something is entered.
		alert("Latitude Needed");
		oCont.focus();
		return true;
	}
	
	dLat = parseLL(oCont.value, 90.0, "NS");
	if (typeof dLat != "number"){
		alert("Latitude is not valid:-\n" + dLat);
		oCont.focus();
	} else {
		//	Add a latitude property to the text input element.
		oCont.degrees = dLat;
	}
	return true;
}


//-----------------------------------------------------------------------------
//	Check a longitude for validity.
//-----------------------------------------------------------------------------
function lngcheck(oCont)
//	check a longitude on exit from its text box
{
	var		dLng;
	
	if (oCont.value == ""){
		// Make sure something is entered.
		alert("Longitude Needed");
		oCont.focus();
		return true;
	}
	
	dLng = parseLL(oCont.value, 180.0, "EW");
	if (typeof dLng != "number"){
		alert("Longitude is not valid:-\n" + dLng);
		oCont.focus();
	} else {
		//	Add a latitude property to the text input element.
		oCont.degrees = dLng;
	}
	return true;
}

