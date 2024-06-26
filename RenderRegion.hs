module RenderRegion where
import Region
import StencilBufferOperations
import Graphics.Rendering.OpenGL
import Graphics.UI.GLUT
import Control.Monad.State
import Data.IORef
import Control.Monad (when, unless)


data DrawState = DrawState {
  fillColor :: Color3 GLdouble,
  outlineColor :: Color3 GLdouble
} deriving (Show)

type Draw a = StateT DrawState IO a


drawOverWholeStencilBuffer :: DisplayCallback
drawOverWholeStencilBuffer =
      renderPrimitive Quads $ do
        vertex (Vertex2 (-10.0) (-10.0) :: Vertex2 GLfloat)
        vertex (Vertex2 10.0 (-10.0) :: Vertex2 GLfloat)
        vertex (Vertex2 10.0 10.0 :: Vertex2 GLfloat)
        vertex (Vertex2 (-10.0) 10.0 :: Vertex2 GLfloat)

scaleColor3 :: GLdouble -> Color3 GLdouble -> Color3 GLdouble
scaleColor3 factor (Color3 r g b) = 
    Color3 (clamp(r*factor)) (clamp(g*factor)) (clamp(b*factor))
  where
    clamp x = max 0 (min 1 x)

drawWithOutline :: DisplayCallback -> Draw()
drawWithOutline renderObject = do
  state <- Control.Monad.State.get
  liftIO $ do 
    color $ fillColor state
    renderObject

  liftIO $ do
    -- Set the polygon mode to line to draw the outline
    polygonMode $= (Line, Line)
    color $ outlineColor state 
    renderObject
    -- Reset the polygon mode to fill
    polygonMode $= (Fill, Fill)


drawCone :: GLdouble -> GLdouble -> Draw()
drawCone base height = drawWithOutline $ renderObject Solid (Cone base height 40 40)


drawSphere :: GLdouble -> Draw()
drawSphere radius =  drawWithOutline $ renderObject Solid (Sphere' radius 40 40)


drawCube :: GLdouble -> Draw()
drawCube side = drawWithOutline $ renderObject Solid (Cube side)


runDraw :: DrawState -> Draw a -> IO a
runDraw initialState drawAction = evalStateT drawAction initialState


drawTranslate :: Draw() -> PointGS -> Draw()
drawTranslate drawAction (x, y, z) = do
  currentState <- Control.Monad.State.get
  liftIO $ preservingMatrix $ do
    translate $ Vector3 x y z
    evalStateT drawAction currentState


drawRotate :: Draw() -> PointGS -> Draw()
drawRotate drawAction (angleX, angleY, angleZ) = do
  currentState <- Control.Monad.State.get
  liftIO $ preservingMatrix $ do
    rotate angleX $ Vector3 1 0 0
    rotate angleY $ Vector3 0 1 0
    rotate angleZ $ Vector3 0 0 1
    evalStateT drawAction currentState


drawOutside :: Draw() -> Draw()
drawOutside drawAction = do
  prevColorMask <- liftIO $  Graphics.UI.GLUT.get colorMask
  (Position x y, Size width height) <- liftIO $  Graphics.UI.GLUT.get viewport
  -- Check if prevColorMask is Disabled
  let isColorMaskDisabled = case prevColorMask of
        Color4 Disabled Disabled Disabled Disabled -> True
        _ -> False
  -- Get the previous state and save it
  prevStencilTestStatus <- liftIO $ Graphics.UI.GLUT.get stencilTest
  prevStencilFunc <- liftIO $ Graphics.UI.GLUT.get stencilFunc
  prevStencilOp <- liftIO $ Graphics.UI.GLUT.get stencilOp
  prevStencilBuffer <- liftIO $ readStencilBuffer (x, y) (width, height)
  -- if color mask is disabled we need to get the stencil buffer
  when isColorMaskDisabled $ do
    colorMask $= Color4 Disabled Disabled Disabled Disabled
    liftIO $ clear [StencilBuffer]
    liftIO $ do
      stencilOp $= (OpReplace, OpReplace, OpReplace)
      stencilFunc $= (Always, 1, 0xFF)
    drawAction

    -- the gotten stencilBuffer now has to be reversed
    liftIO $ do
      stencilFunc $= (Equal, 1, 0xFF)
      -- parameters are fail, passes, passess
      -- so if it is equal to 1 than it needs to be 0 -> Decr
      -- if it is not equal to 1 make it 1 -> Incr
      stencilOp $= (OpIncr, OpDecr, OpDecr)
      drawOverWholeStencilBuffer

  -- if color mask is not disabled we need to draw
  unless isColorMaskDisabled $ do
    liftIO $ do
      clear [StencilBuffer]
      colorMask $= Color4 Disabled Disabled Disabled Disabled
      stencilOp $= (OpReplace, OpReplace, OpReplace)
      stencilFunc $= (Always, 1, 0xFF)
    drawAction

    -- the gotten stencilBuffer now has to be reversed
    liftIO $ do
      stencilFunc $= (Equal, 1, 0xFF)
      -- parameters are fail, passes, passess
      -- so if it is equal to 1 than it needs to be 0 -> Decr
      -- if it is not equal to 1 make it 1 -> Incr
      stencilOp $= (OpIncr, OpDecr, OpDecr)
      drawOverWholeStencilBuffer
    
    -- This part is needed to both handle if the Outside is in root or in an IntersectGS
    -- save the current StencilBuffer
    stencilBufferFromOutside <- liftIO $ readStencilBuffer (x, y) (width, height)
    -- now intersect it with the previous
    intersectionStencilBuffer <- liftIO $ computeIntersection (width, height) prevStencilBuffer stencilBufferFromOutside
    -- and now set it as the current StencilBuffer
    liftIO $ do
      clear [StencilBuffer]
      writeStencilBuffer (x, y) (width, height) intersectionStencilBuffer
    -- Now draw everywhere based on this
    colorMask $= Color4 Enabled Enabled Enabled Enabled
    liftIO $ do
      stencilFunc $= (Equal, 1, 0xFF)
      stencilOp $= (OpKeep, OpKeep, OpKeep)
      drawOverWholeStencilBuffer
    
    -- restore previous StencilBuffer
    liftIO $ writeStencilBuffer (x, y) (width, height) prevStencilBuffer

  -- Restore the stencil test state
  colorMask $= prevColorMask
  liftIO $ do
    stencilTest $= prevStencilTestStatus
    stencilFunc $= prevStencilFunc
    stencilOp $= prevStencilOp


-- Main function to draw the intersection
drawIntersection :: Draw() -> Draw() -> Draw()
drawIntersection drawAction1 drawAction2 = do
  (Position x y, Size width height) <- liftIO $ Graphics.UI.GLUT.get viewport

  -- Get the previous state and save it
  prevStencilTestStatus <- liftIO $ Graphics.UI.GLUT.get stencilTest
  prevColorMask <- liftIO $ Graphics.UI.GLUT.get colorMask
  prevStencilFunc <- liftIO $ Graphics.UI.GLUT.get stencilFunc
  prevStencilOp <- liftIO $ Graphics.UI.GLUT.get stencilOp
  prevStencilBuffer <- liftIO $ readStencilBuffer (x, y) (width, height)

  -- Check if prevColorMask is Disabled
  let isColorMaskDisabled = case prevColorMask of
        Color4 Disabled Disabled Disabled Disabled -> True
        _ -> False

  stencilTest $= Enabled
  colorMask $= Color4 Disabled Disabled Disabled Disabled

  -- Get first mask
  liftIO $ clear [StencilBuffer]
  liftIO $ do
    stencilFunc $= (Always, 1, 0xFF)
    stencilOp $= (OpReplace, OpReplace, OpReplace)
  drawAction1
  stencilBuffer1 <- liftIO $ readStencilBuffer (x, y) (width, height)

  -- if color mask is disabled we need to get the stencil buffer
  when isColorMaskDisabled $ do
    -- Get second mask
    liftIO $ clear [StencilBuffer]
    liftIO $ do
      stencilFunc $= (Always, 1, 0xFF)
      stencilOp $= (OpReplace, OpReplace, OpReplace)
    drawAction2
    stencilBuffer2 <- liftIO $ readStencilBuffer (x, y) (width, height)

    -- Compute the intersection of the two stencil buffers
    intersectionStencilBuffer <- liftIO $ computeIntersection (width, height) stencilBuffer1 stencilBuffer2
    -- the intersectionStencilBuffer will be set after exiting this function in this case
    liftIO $ do
      clear [StencilBuffer]
      writeStencilBuffer (x, y) (width, height) intersectionStencilBuffer

  -- Now you know something really has to be drawn
  unless isColorMaskDisabled $ do
    -- Restore the intersection result to the stencil buffer
    fullIntersectionForDrawingStencilBuffer <- liftIO $ computeIntersection (width, height) prevStencilBuffer stencilBuffer1
    liftIO $ do
      colorMask $= prevColorMask
      clear [StencilBuffer]
      writeStencilBuffer (x, y) (width, height) fullIntersectionForDrawingStencilBuffer
      -- Final rendering based on the intersection result
      stencilFunc $= (Equal, 1, 0xFF)
      stencilOp $= (OpKeep, OpKeep, OpKeep)
      -- Draw your final scene based on the intersection result
      putStrLn "Drawing"
    drawAction2

    -- fill StencilBuffer the stencil buffer before calling this function
    liftIO $ do
      clear [StencilBuffer]
      writeStencilBuffer (x, y) (width, height) prevStencilBuffer
    

  -- Restore the stencil test state
  liftIO $ do
    colorMask $= prevColorMask
    stencilTest $= prevStencilTestStatus
    stencilFunc $= prevStencilFunc
    stencilOp $= prevStencilOp


drawUnion :: Draw() -> Draw() -> Draw()
drawUnion drawAction1 drawAction2 = do
    prevColorMask <- liftIO $ Graphics.UI.GLUT.get colorMask
    -- Check if prevColorMask is Disabled
    let isColorMaskDisabled = case prevColorMask of
          Color4 Disabled Disabled Disabled Disabled -> True
          _ -> False
    -- if color mask is disabled we need to get the stencil buffer
    when isColorMaskDisabled $ do
      (Position x y, Size width height) <- liftIO $ Graphics.UI.GLUT.get viewport
      -- Get the previous state and save it
      prevStencilTestStatus <- liftIO $ Graphics.UI.GLUT.get stencilTest
      prevStencilFunc <- liftIO $ Graphics.UI.GLUT.get stencilFunc
      prevStencilOp <- liftIO $ Graphics.UI.GLUT.get stencilOp
      prevStencilBuffer <- liftIO $ readStencilBuffer (x, y) (width, height)
      -- set 
      stencilTest $= Enabled
      colorMask $= Color4 Disabled Disabled Disabled Disabled
      -- Get first mask
      liftIO $ clear [StencilBuffer]
      liftIO $ do
        stencilFunc $= (Always, 1, 0xFF)
        stencilOp $= (OpReplace, OpReplace, OpReplace)
      drawAction1
      stencilBuffer1 <- liftIO $ readStencilBuffer (x, y) (width, height)
      -- Get second mask
      liftIO $ clear [StencilBuffer]
      liftIO $ do
        stencilFunc $= (Always, 1, 0xFF)
        stencilOp $= (OpReplace, OpReplace, OpReplace)
      drawAction2
      stencilBuffer2 <- liftIO $ readStencilBuffer (x, y) (width, height)
      -- Compute the union of the two stencil buffers
      unionStencilBuffer <- liftIO $ computeUnion (width, height) stencilBuffer1 stencilBuffer2
      -- write the unionStencilBuffer to the StencilBuffer
      liftIO $ do
        clear [StencilBuffer]
        writeStencilBuffer (x, y) (width, height) unionStencilBuffer
      -- Restore the stencil test state
      liftIO $ do 
        colorMask $= prevColorMask
        stencilTest $= prevStencilTestStatus
        stencilFunc $= prevStencilFunc
        stencilOp $= prevStencilOp
    
    -- if color mask is not disabled we need to draw
    unless isColorMaskDisabled $ do
      drawAction1
      drawAction2