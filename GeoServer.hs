{-# OPTIONS_GHC -Wno-missing-fields #-}
module GeoServer where
import Graphics.UI.GLUT
import Region
import RenderRegion
import PreMadeRegions


foldRegion :: RegionAlgebra a -> Region -> a
foldRegion alg (SphereGS r)       = ra_sphere alg r
foldRegion alg (CubeGS s)         = ra_cube alg s
foldRegion alg (TranslateGS r p)  = ra_translate alg (foldRegion alg r) p
foldRegion alg (OutsideGS r)      = ra_outside alg (foldRegion alg r)
foldRegion alg (IntersectionGS r1 r2) = ra_intersection alg (foldRegion alg r1) (foldRegion alg r2)
foldRegion alg (UnionGS r1 r2) = ra_union alg (foldRegion alg r1) (foldRegion alg r2)

distanceFromCenterConeYAxis :: Double -> Double -> (Double -> Double)
distanceFromCenterConeYAxis base height =
  let slope = height/base
    in \y -> slope * y + base



-- inRegion interpretation
inRegionAlgebra :: RegionAlgebra (PointGS -> Bool)
inRegionAlgebra = RAlg {
  ra_sphere = \r (x, y, z) -> x^2 + y^2 + z^2 <= r^2,
  ra_cube = \s (x, y, z) -> abs x <= s/2 && abs y <= s/2 && abs z <= s/2,
  ra_cone = \b h (x, y, z) -> let d = distanceFromCenterConeYAxis b h y 
                                in abs x <= d && abs x >= b && abs z <= d && abs z >= b,
  ra_translate = \r (x0, y0, z0) (x, y , z) -> r (x - x0, y - y0, z - z0),
  ra_rotate = undefined,
  ra_outside = \r p -> not (r p),
  ra_intersection = \r1 r2 p -> r1 p && r2 p,
  ra_union = \r1 r2 p -> r1 p || r2 p
}

-- renderRegion interpretation
renderAlgebra :: RegionAlgebra (Draw())
renderAlgebra = RAlg {
  ra_sphere = drawSphere,
  ra_cube = drawCube,
  ra_cone = drawCone,
  ra_translate = drawTranslate,
  ra_rotate = drawRotate,
  ra_outside = drawOutside,
  ra_intersection = drawIntersection,
  ra_union = drawUnion
}

-- serialize interpretation
serializeAlgebra :: RegionAlgebra String
serializeAlgebra = RAlg {
  ra_sphere = \r -> "SphereGS " ++ show r,
  ra_cube = \s -> "CubeGS " ++ show s,
  ra_cone = \b h -> "ConeGS " ++ show b ++ " " ++ show h, 
  ra_translate = \r p -> "TranslateGS (" ++ r ++ ") " ++ show p,
  ra_rotate = \r p -> "RotateGS (" ++ r ++ ") " ++ show p,
  ra_outside = \r -> "OutsideGS (" ++ r ++ ")",
  ra_intersection = \r1 r2 -> "IntersectionGS (" ++ r1 ++ ") (" ++ r2 ++ ")",
  ra_union = \r1 r2 -> "UnionGS (" ++ r1 ++ ") (" ++ r2 ++ ")"
}


-- display logic
displayRegion :: Region -> IO ()
displayRegion region = do
  (_progName, _args) <- getArgsAndInitialize
  _window <- createWindow "GeoServer"
  displayCallback $= drawing region
  mainLoop

drawing :: Region -> DisplayCallback
drawing region = do
    clear [ ColorBuffer, DepthBuffer, StencilBuffer]

    -- This is needed for intersections
    stencilTest $= Enabled
    clear [StencilBuffer]
    colorMask $= Color4 Disabled Disabled Disabled Disabled
    stencilFunc $= (Always, 1, 0xFF)
    stencilOp $= (OpReplace, OpReplace, OpReplace)
    renderPrimitive Quads $ do
      color (Color3 1.0 0.0 0.0 :: Color3 GLfloat)
      vertex (Vertex2 (-1.0) (-1.0) :: Vertex2 GLfloat)
      vertex (Vertex2 1.0 (-1.0) :: Vertex2 GLfloat)
      vertex (Vertex2 1.0 1.0 :: Vertex2 GLfloat)
      vertex (Vertex2 (-1.0) 1.0 :: Vertex2 GLfloat)
    colorMask $= Color4 Enabled Enabled Enabled Enabled
    stencilTest $= Enabled
    -- until here 

    runDraw (DrawState (Color3 1 0 0) (Color3 0.8 0 0)) (foldRegion renderAlgebra region)
    flush
